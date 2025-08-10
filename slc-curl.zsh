#!/usr/bin/env zsh

: '# Check links using curl (2), v2.6.1'
: '#'
: '# (C) Dmitry Muratov <https://github.com/dmuratov-als/shell-link-checker>'
: '# CC0-1.0'

main() {
  : '# START OF CUSTOMIZABLE SECTION'

  : '# Specify a project name*'
  typeset          project=''

  : '# Specify HTTP status codes to exclude from the broken link report (vbar-separated)'
  typeset        skip_code=''

  : '# Specify a regexp (POSIX ERE, case-insensitive) for a custom search'
  typeset   custom_query_1=''
  typeset   custom_query_2=''
  typeset   custom_query_3=''
  typeset   custom_query_4=''
  typeset   custom_query_5=''

  : '# Specify curl options (except for those after the ${curl_cmd_opts[@]} lines below)'
  typeset -a curl_cmd_opts=(
    curl
      --disable
      --verbose
      --no-progress-meter
      --stderr -
      --write-out '\nout_errormsg: %{errormsg}\nout_num_redirects: %{num_redirects}\nout_response_code: %{response_code}\nout_size_header: %{size_header}\nout_size_download: %{size_download}\nout_time_total: %{time_total}\nout_url: %{url}\n\n'
      --location
      --referer ';auto'
  )

  : '# Specify a path of the project'
  typeset -h          path=~

  : '# END OF CUSTOMIZABLE SECTION'


  true ${project:?Specify a project name.}

  set -o LOCAL_TRAPS \
      -o WARN_CREATE_GLOBAL \
      +o UNSET

  zmodload -F zsh/files b:mv b:rm
  zmodload zsh/mapfile

  typeset -i SECONDS=0

  true ${path::=${path%/}/${project}}
  cd -q ${path}(/N) \
    && trap 'cd -q ~-' EXIT

  typeset -a file_wget_links=( ${(f)mapfile[${project}-wget-links.txt]-} )
  typeset file_wget_links_refs=$( () { print -- ${1-} } "${project}-wget-links-refs.tsv"(N) )
  typeset file_wget_log=$( () { print -- ${1-} } "${project}-wget.log"(|.zst)(N) )
  typeset -a file_wget_sitemap=( ${(fL)mapfile[${project}-wget-sitemap.txt]-} )
  typeset file_broken_links="${project}-broken-links-%D{%F-%H%M}.tsv"
  typeset file_curl_log="${project}-curl.log"
  typeset file_curl_summary="${project}-curl-summary.tsv"
  typeset file_curl_finish_tmp==()

  true "${file_wget_links:?File missing.}"
  true ${file_wget_links_refs:?File missing.}
  true ${file_wget_log:?File missing.}
  true "${file_wget_sitemap:?File missing.}"

  () {
    if [[ -e ${file_curl_log} || \
          -e "${file_curl_log}.zst" || \
          -e ${file_curl_summary} ]]; then
      typeset REPLY
      if read -q $'?\342\200\224'" Overwrite existing files in ${${path:t2}%/}/? (y/n) "; then
        builtin rm -s -- ${file_curl_log:+${file_curl_log}(|.zst)(N)} \
                         ${file_curl_summary:+${file_curl_summary}(N)}
        print -l
      else
        : '# Restore options if we exit now, skipping the point of return from the main() function'
        trap 'set -o LOCAL_OPTIONS' EXIT
        exit_fn
      fi
    fi
  }

  sort_file_summary() {
    if [[ -s ${file_curl_summary} ]]; then
      { read -e -r
        sort -d -f -k2,2r -k1,1 -t $'\t'
      } < ${file_curl_summary} > "${file_curl_summary}.tmp" \
          && builtin mv -- ${file_curl_summary}{.tmp,}
    fi
  }

  cleanup() {
    if ! [[ -s ${file_curl_summary} ]]; then
      builtin rm -- ${file_curl_summary}
    fi

    () {
      if command -v zstd >/dev/null; then
        typeset REPLY
        typeset -g zstd_output
        if ! read -t 15 -q $'?\n\342\200\224 Keep the log file uncompressed? (y/N) '; then
          zstd --force --rm -- ${file_curl_log} 2>&1 | read zstd_output
        fi
      fi
    }

    () {
      set -o EXTENDED_GLOB \
          -o HIST_SUBST_PATTERN

      zmodload -F zsh/stat +b:stat

      typeset file
      typeset -a files=(
        ${file_broken_links:+${file_broken_links}(N)}
        ${file_curl_summary:+${file_curl_summary}(N)}
        ${file_curl_log:+${file_curl_log}(|.zst)(N)}
      )
      typeset -A fstat
      typeset -a -i match mbegin mend
      typeset MATCH MBEGIN MEND

      print -l -- "\nCREATED FILES"
      for file in ${files[@]}; do
        builtin stat -A fstat -n +size -- ${file:P}
        printf "%14sB\t%s\n" ${(v)fstat:fs/%(#b)([^,])([^,](#c3)(|,*))/${match[1]},${match[2]}} \
                            ${${zstd_output:+${(k)fstat/%.zst/.zst  ${${zstd_output:s/(#m)[[:digit:].]##\%/${MATCH}}[${MBEGIN},${MEND}]}}}:-${(k)fstat}}
      done
    }
  }

  trap 'sort_file_summary
        cleanup' INT TERM QUIT

  ( () {
      typeset -g -l -T -U IN_SCOPE in_scope "|"
      typeset -i line_index
      typeset -a wget_log_clip

      _load_log_clip() {
        typeset REPLY
        while read -r; do
          if [[ ${REPLY} == 'Setting'* ]]; then
            wget_log_clip+=( ${REPLY} )
          else
            break
          fi
        done
      }
      if [[ ${file_wget_log:e} == 'log' ]]; then
        _load_log_clip < ${file_wget_log}
      elif [[ ${file_wget_log:e} == 'zst' ]]; then
        if command -v zstdcat >/dev/null; then
          zstdcat --quiet -- ${file_wget_log} \
            | _load_log_clip
        fi
      fi

      : '# retrieve the domain(s) to define the in-scope URLs'
      if (( line_index=${wget_log_clip[(I)Setting --domains*]} )); then
        in_scope=( ${${(s<,>)${wget_log_clip[${line_index}]:31}}/#/https?://} )
      else
        in_scope=( ${${${file_wget_sitemap#*//}%%/*}/#/https?://} )
      fi

      : '# retrieve the credentials, unless they are specified explicitly in $curl_cmd_opts above'
      if (( ! ${(M)#curl_cmd_opts[@]:#--user} )); then
        if (( line_index=${wget_log_clip[(I)Setting --http-user*]} )); then
          typeset -a auth=( ${wget_log_clip[${line_index}]:34} )
          if (( line_index=${wget_log_clip[(I)Setting --http-password*]} )); then
            auth+=( ${wget_log_clip[${line_index}]:42} )
            curl_cmd_opts+=(
              --user
              ${(j<:>)auth[@]}
            )
          fi
        fi
      fi
    }

    : '# one curl invocation per each URL allows checking unlimited number of URLs while keeping memory footprint small'
    for url in ${file_wget_links[@]}; do
      if [[ ! ${url} =~ ^https?: ]]; then
        print -r -- "out_url: ${url}"
      else
        if [[ ${(L)url} =~ ^(${IN_SCOPE}) ]]; then
          if (( ${file_wget_sitemap[(Ie)${(L)url}]} )); then
            ${curl_cmd_opts[@]:s/out_url:/out_full_download\\n&} \
              ${url}
          else
            ${curl_cmd_opts[@]} \
              --head \
              ${url}
          fi
        elif [[ ${(L)url} =~ ^https?://((.*)+\.)?vk\.(ru|com) ]]; then
          : '# brew coffee with a HEAD-less teapot'
          ${curl_cmd_opts[@]:/(${curl_cmd_opts[${curl_cmd_opts[(ie)--user]}]-}|${curl_cmd_opts[${curl_cmd_opts[(ie)--user]}+1]-})} \
            --fail \
            --output '/dev/null' \
            ${url}
        else
          ${curl_cmd_opts[@]:/(${curl_cmd_opts[${curl_cmd_opts[(ie)--user]}]-}|${curl_cmd_opts[${curl_cmd_opts[(ie)--user]}+1]-})} \
            --head \
            ${url}
        fi
      fi
    done > ${file_curl_log} \
      | gawk \
             -v IGNORECASE=1 \
             -v OFS='\t' \
             -v RS='\r?\n' \
             -v custom_query_1="@/${custom_query_1:-"CUSTOM QUERY"}/" \
             -v custom_query_2="@/${custom_query_2:-"CUSTOM QUERY"}/" \
             -v custom_query_3="@/${custom_query_3:-"CUSTOM QUERY"}/" \
             -v custom_query_4="@/${custom_query_4:-"CUSTOM QUERY"}/" \
             -v custom_query_5="@/${custom_query_5:-"CUSTOM QUERY"}/" \
             -v file_curl_summary=${file_curl_summary} \
             -v file_curl_finish_tmp=${file_curl_finish_tmp} \
             -v links_total=${#file_wget_links[@]} \
             -v no_parser_mx=$(command -v host >/dev/null)$? \
             -v no_parser_xml=$(command -v xmllint >/dev/null)$? '
          BEGIN {
            print("URL",
                  "CODE (LAST HOP IF REDIRECT)\342\206\223",
                  "CONTENT-TYPE",
                  "SIZE, KB",
                  "REDIRECT",
                  "NUM REDIRECTS",
                  "TITLE",
                  "og:title",
                  "og:description",
                  "description",
                  custom_query_1,
                  custom_query_2,
                  custom_query_3,
                  custom_query_4,
                  custom_query_5) > file_curl_summary
          }

          /^< Content-Length:/ {
            if ($3 != 0) {
              size = sprintf("%.f", $3 / 1024)
            }
            if (size == 0) {
              size = 1
            }
          }

          /^< Content-Type:/ {
            split($0, a_ctype, /[:;=]/)
            type = a_ctype[2]
            gsub(/^ +| +$/, "", type)

            charset = a_ctype[4]
            gsub(/^ +| +$/, "", charset)
            if (! charset) {
              charset = "UTF-8"
            }
            delete a_ctype
          }

          /^< Location:/ {
            redirect = $3
          }

          # These error messages are from curl/src/tool_operate.c.
          /^Warning: Problem (\(retrying all errors\)|(: (timeout|connection refused|HTTP error)))/ {
            f_error = 1
          }

          /<TITLE[^>]*>/, /<\/TITLE>/ {
            mult_title++
            if (mult_title > 1 && ! f_error) {
              title = "MULTIPLE TITLE"
            } else if (! no_parser_xml) {
              gsub(/\047/, "\047\\\047\047", $0)
              sub(/<TITLE/, "<meta http-equiv='\''Content-Type'\'' content='\''charset=" charset "'\'' />&", $0)
              cmd = "xmllint \
                     --html \
                     --xpath '\''//title'\'' \
                     - 2>/dev/null <<< '\''"$0"'\''"
              cmd | getline title
              close(cmd)
              cmd = ""

              gsub(/^<TITLE[^>]*>|<\/TITLE>$/, "", title)
              if (! title) {
                title = "EMPTY TITLE"
              }
            } else if (! title) {
              title = "No xmllint installed"
            }
          }

          /<META.*og:title/, />/ {
            mult_og_title++
            if (mult_og_title > 1) {
              og_title = "MULTIPLE OG:TITLE"
            } else if (! no_parser_xml) {
              gsub(/\047/, "\047\\\047\047", $0)
              sub(/<META/, "<meta http-equiv='\''Content-Type'\'' content='\''charset=" charset "'\'' />&", $0)
              cmd = "xmllint \
                       --html \
                       --xpath '\''string(//meta[@property=\"og:title\"]/@content)'\'' \
                       - 2>/dev/null <<< '\''"$0"'\''"
              cmd | getline og_title
              close(cmd)
              cmd = ""
            } else if (! og_title) {
              og_title = "No xmllint installed"
            }
          }

          /<META.*og:description/, />/ {
            mult_og_desc++
            if (mult_og_desc > 1) {
              og_desc = "MULTIPLE OG:DESCRIPTION"
            } else if (! no_parser_xml) {
              gsub(/\047/, "\047\\\047\047", $0)
              sub(/<META/, "<meta http-equiv='\''Content-Type'\'' content='\''charset=" charset "'\'' />&", $0)
              cmd = "xmllint \
                       --html \
                       --xpath '\''string(//meta[@property=\"og:description\"]/@content)'\'' \
                       - 2>/dev/null <<< '\''"$0"'\''"
              cmd | getline og_desc
              close(cmd)
              cmd = ""
            } else if (! og_desc) {
              og_desc = "No xmllint installed"
            }
          }

          /<META.*name=\042description\042/, />/ {
            mult_desc++
            if (mult_desc > 1) {
              desc = "MULTIPLE DESCRIPTION"
            } else if (! no_parser_xml) {
              gsub(/\047/, "\047\\\047\047", $0)
              sub(/<META/, "<meta http-equiv='\''Content-Type'\'' content='\''charset=" charset "'\'' />&", $0)
              cmd = "xmllint \
                       --html \
                       --xpath '\''string(//meta[@name=\"description\"]/@content)'\'' \
                       - 2>/dev/null <<< '\''"$0"'\''"
              cmd | getline desc
              close(cmd)
              cmd = ""
            } else if (! desc) {
              desc = "No xmllint installed"
            }
          }

          custom_query_1 != "CUSTOM QUERY" {
            if ($0 ~ custom_query_1) {
              custom_match_1 = "\342\234\223"
            }
          }

          custom_query_2 != "CUSTOM QUERY" {
            if ($0 ~ custom_query_2) {
              custom_match_2 = "\342\234\223"
            }
          }

          custom_query_3 != "CUSTOM QUERY" {
            if ($0 ~ custom_query_3) {
              custom_match_3 = "\342\234\223"
            }
          }

          custom_query_4 != "CUSTOM QUERY" {
            if ($0 ~ custom_query_4) {
              custom_match_4 = "\342\234\223"
            }
          }

          custom_query_5 != "CUSTOM QUERY" {
            if ($0 ~ custom_query_5) {
              custom_match_5 = "\342\234\223"
            }
          }

          /^out_errormsg:/ {
            if ($2 != 0) {
              errormsg = substr($0, 15)
            }
          }

          /^out_num_redirects:/ {
            if ($2 != 0) {
              num_redirects = $2
            }
          }

          /^out_response_code:/ {
            response_code = $2
          }

          /^out_size_header:/ {
            if ($2 != 0) {
              downloaded += $2
            }
          }

          /^out_size_download:/ {
            if ($2 != 0) {
              downloaded += $2
            }
          }

          /^out_time_total:/ {
            if ($2 != 0) {
              time_total = sprintf("%.2fs", $2)
            }
          }

          /^out_full_download$/ {
            if (! title && ! errormsg) {
              title = "NO TITLE"
            }
          }

          /^out_url:/ {
            url = $2

            checked += 1
            if (! time_total) {
              time_total = " --"
            }
            printf "%6d%s%-6d\t%s\t%s\n", checked, "/", links_total, time_total, url

            if (url !~ /^https?:/ && url ~ /^([[:alnum:]+.-]+):/) {
              if (url ~ /^mailto:/) {
                if (url ~ /[,;]/ && url ~ /(@.+){2,}/) {
                  code = "Mailbox list not supported"
                } else if (url ~ /^mailto:(%20)*[[:alnum:].!#$%&\047*+/=?^_`{|}~-]+@[[:alnum:].-]+\.[[:alpha:]]{2,64}(%20)*(\?.*)?$/) {
                  if (! no_parser_mx) {
                    cmd = "zsh -c '\''host -t MX ${${${${:-$(<<<"url")}#*@}%%\\?*}//(%20)/}'\''"
                    cmd | getline mx_check
                    close(cmd)
                    cmd = ""

                    if (mx_check ~ /mail is handled by .{4,}/) {
                      code = "MX found"
                    } else {
                      code = mx_check
                    }
                  } else {
                    code = "No Host utility installed"
                  }
                } else {
                  code = "Incorrect email syntax"
                }
              } else {
                code = "Custom URL scheme"
              }
            } else if (response_code != "000") {
              code = response_code
            } else if (errormsg) {
              code = errormsg
            }

            print(url,
                  code,
                  type,
                  size,
                  redirect,
                  num_redirects,
                  "\042" gensub(/\042/, "\042&", "g", title)    "\042",
                  "\042" gensub(/\042/, "\042&", "g", og_title) "\042",
                  "\042" gensub(/\042/, "\042&", "g", og_desc)  "\042",
                  "\042" gensub(/\042/, "\042&", "g", desc)     "\042",
                  custom_match_1,
                  custom_match_2,
                  custom_match_3,
                  custom_match_4,
                  custom_match_5) > file_curl_summary

            f_error = 0
            charset = ""
            code = ""
            custom_match_1 = ""
            custom_match_2 = ""
            custom_match_3 = ""
            custom_match_4 = ""
            custom_match_5 = ""
            desc = ""
            errormsg = ""
            mult_desc = ""
            mult_og_desc = ""
            mult_og_title = ""
            mult_title = ""
            mx_check = ""
            num_redirects = ""
            og_desc = ""
            og_title = ""
            redirect = ""
            response_code = ""
            size = ""
            time_total = ""
            title = ""
            type = ""
            url = ""
          }

          END {
            if (downloaded) {
              split("B,K,M,G", unit, ",")
              rank = int(log(downloaded) / log(1024))
              printf("%.1f%s\n", downloaded / (1024 ^ rank), unit[rank + 1]) > file_curl_finish_tmp
            }
          }' \
      && sort_file_summary \
      && { true ${file_broken_links::=${(%)file_broken_links}}
           gawk -v FS='\t' \
                -v OFS='\t' \
                -v file_broken_links=${file_broken_links} \
                -v skip_code="@/^(MX found|Custom URL scheme|200${skip_code:+|${skip_code}})/" '
              NR == FNR && $2 !~ skip_code {
               count += 1
               if (count == 1) {
                 header = "E R R O R S" OFS
                 subheader = $1 OFS $2
               } else {
                 if (count == 2) {
                   print(header RT subheader) > file_broken_links
                 }
                 print($1, $2) > file_broken_links
                 seen[$1]++
                 next
               }
             }

             FNR == 1 {
               if (count > 1) {
                 print(OFS, RT "L I N K S", RT "BROKEN LINK", "REFERER") > file_broken_links
               }
             }

             $1 in seen {
               print($1, $2) > file_broken_links
             }' ${file_curl_summary} ${file_wget_links_refs} \
         } \
      && { print -P -- "\nFINISHED --%D{%F %T}--"

           print -n -- 'Total wall clock time:'
           typeset -i t=${SECONDS}
           typeset -i d=$(( t/60/60/24 ))
           typeset -i h=$(( t/60/60%24 ))
           typeset -i m=$(( t/60%60 ))
           typeset -i s=$(( t%60 ))
           if [[ ${d} > 0 ]]; then
             print -n -- " ${d}d"
           fi
           if [[ ${h} > 0 ]]; then
             print -n -- " ${h}h"
           fi
           if [[ ${m} > 0 ]]; then
             print -n -- " ${m}m"
           fi
           if [[ ${s} > 0 ]]; then
             print -n -- " ${s}s"
           fi

           if [[ -s ${file_curl_finish_tmp} ]]; then
             print -l -- "\nDownloaded: $(< ${file_curl_finish_tmp})"
           fi
         }

    if command -v osascript >/dev/null; then
      osascript -e "display notification \"${project}\" with title \"Curl completed\" sound name \"Submarine\""
    elif command -v notify-send >/dev/null; then
      notify-send ${project} 'Curl completed' --icon='dialog-information'
    fi

    cleanup
  )

  set -o LOCAL_OPTIONS
}


: '# Cancel the execution of the script, whether it is pasted (runs in the current shell used by the terminal and requires the return command to not cause the shell to exit) or sourced (runs in a child shell and requires the exit command).'
exit_fn() {
  if [[ -n ${argv:-} ]]; then
    print -l -- ${argv}
  fi

  set -o ERR_RETURN
  return 1
  set +o ERR_RETURN
} >&2


: '# Prerequisites check'
check() {
  typeset -A programs=(
    'curl,7.75.0' 'NR == 1 { print $2 }'
    'gawk,5.0.0'  'NR == 1 { print $3 }'
    'sort'        ''
    'zsh,5.5.1'   'NR == 1 { print $2 }'
  )
  for program awk_code in "${(@kv)programs}"; do
    [[ -n ${program} ]] \
      && { command -v ${program%,*} >/dev/null \
             || exit_fn "${program%,*} is required for the script to work."
         }
    [[ -n ${awk_code} ]] \
      && { () { [[ $1 == ${${(On)@}[1]} ]] } $(${program%,*} --version | awk ${awk_code}) ${program#*,} \
             || exit_fn "The oldest supported version of ${program%,*} is ${program#*,}."
         }
  done

  : '# Load zsh modules to check if they and their features are available, and then unload them. They will be loaded later, if and when necessary'
  zmodload -F zsh/files b:mkdir b:rm \
    && zmodload -u -i zsh/files \
    || exit_fn

  zmodload zsh/mapfile \
    && zmodload -u -i zsh/mapfile \
    || exit_fn

  zmodload -F zsh/stat +b:stat \
    && zmodload -u -i zsh/stat \
    || exit_fn
}

check \
  && LC_ALL='C' main

: '# end'
