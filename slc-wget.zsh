#!/usr/bin/env zsh

: '# Gather links using Wget (1), v2.6.1'
: '#'
: '# (C) Dmitry Muratov <https://github.com/dmuratov-als/shell-link-checker>'
: '# CC0-1.0'

main() {
  : '# START OF CUSTOMIZABLE SECTION'

  : '# Specify a project name*'
  typeset        project=''

  : '# Specify a URL or a URL list file*'
  typeset        address=''

  : '# Specify a non-null value to exclude external links (except the mailto and tel URL schemes). Mutually exclusive with $subtree_only.'
  typeset  internal_only=''

  : '# Specify a non-null value to exclude links up the $address tree (a trailing slash indicates a directory). Mutually exclusive with $internal_only, but takes precedence.'
  typeset   subtree_only=''

  : '# Specify a regexp (POSIX ERE, case-insensitive) to exclude links from the absolute links report'
  typeset skip_links_abs=''

  : '# Specify Wget options (except those after the "wget" command below)'
  typeset -a   wget_opts=(
    --level=inf
    --no-parent
  )

  : '# Specify a path for the project'
  typeset -h        path=~

  : '# END OF CUSTOMIZABLE SECTION'


  true ${project:?Specify a project name.}
  true ${address:?Specify a URL or a URL list file.}

  set -o LOCAL_TRAPS \
      -o WARN_CREATE_GLOBAL \
      +o UNSET

  zmodload -F zsh/files b:mkdir b:rm

  if [[ -s ${address} ]]; then
    zmodload zsh/mapfile
    typeset file_address=${address}
    typeset -T -U ADDRESS address=( ${(f)mapfile[${file_address}]} )
  fi

  builtin mkdir -p ${path::=${path%/}/${project}}
  cd -q ${path} \
    && trap 'cd -q ~-' EXIT

  typeset file_wget_errors="${project}-wget-errors.tsv"
  typeset file_wget_links="${project}-wget-links.txt"
  typeset file_wget_links_abs_refs="${project}-wget-links-abs-refs.tsv"
  typeset file_wget_links_refs="${project}-wget-links-refs.tsv"
  typeset file_wget_log="${project}-wget.log"
  typeset file_wget_sitemap="${project}-wget-sitemap.txt"
  typeset file_wget_sitemap_tree="${project}-wget-sitemap-tree.txt"
  typeset file_wget_finish_tmp==()

  () {
    if [[ -e ${file_wget_errors} || \
          -e ${file_wget_links} || \
          -e ${file_wget_links_abs_refs} || \
          -e ${file_wget_links_refs} || \
          -e ${file_wget_log} || \
          -e "${file_wget_log}.zst" || \
          -e ${file_wget_sitemap} || \
          -e ${file_wget_sitemap_tree} ]]; then
      typeset REPLY
      if read -q $'?\342\200\224'" Overwrite existing files in ${${path:t2}%/}/? (y/n) "; then
        builtin rm -s -- ${file_wget_errors:+${file_wget_errors}(N)} \
                         ${file_wget_links:+${file_wget_links}(N)} \
                         ${file_wget_links_abs_refs:+${file_wget_links_abs_refs}(N)} \
                         ${file_wget_links_refs:+${file_wget_links_refs}(N)} \
                         ${file_wget_log:+${file_wget_log}(|.zst)(N)} \
                         ${file_wget_sitemap:+${file_wget_sitemap}(N)} \
                         ${file_wget_sitemap_tree:+${file_wget_sitemap_tree}(N)}
        print -l
      else
        : '# Restore options if we exit now, skipping the point of return from the main() function'
        trap 'set -o LOCAL_OPTIONS' EXIT
        exit_fn
      fi
    fi
  }

  cleanup() {
    () {
      typeset file
      for file in ${file_wget_errors} \
                  ${file_wget_links} \
                  ${file_wget_links_abs_refs} \
                  ${file_wget_sitemap}; do
        if [[ -s ${file} ]]; then
          sort -o "./${file}"{,}
        fi
      done

      if [[ -s ${file_wget_links_refs} ]]; then
        sort -u -o "./${file_wget_links_refs}"{,}
      fi
    }

    gawk -F '/' \
         -v file_wget_sitemap_tree=${file_wget_sitemap_tree} '
      NR == 1 {
        offset_start = NF
      }
      {
        offset = offset_start
        path = ""
        gsub(/\//, "/1", $0)
        if (! /\/1$/) {
          sub(/$/, "/2", $0)
        }
        while (offset < NF) {
          offset++
          path = path "|  "
        }
        gsub(/\/1/, "/", $0)
        sub(/\/2$/, "", $0)
        print(path "|--", $0) > file_wget_sitemap_tree
      }' ${file_wget_sitemap} 2>/dev/null

    () {
      if command -v zstd >/dev/null; then
        typeset REPLY
        typeset -g zstd_output
        if ! read -t 15 -q $'?\n\342\200\224 Keep the log file uncompressed? (y/N) '; then
          zstd --force --rm -- ${file_wget_log} 2>&1 | read zstd_output
        fi
      fi
    }

    () {
      set -o EXTENDED_GLOB \
          -o HIST_SUBST_PATTERN

      zmodload -F zsh/stat +b:stat

      typeset file
      typeset -a files=(
        ${file_wget_errors:+${file_wget_errors}(N)}
        ${file_wget_links:+${file_wget_links}(N)}
        ${file_wget_links_abs_refs:+${file_wget_links_abs_refs}(N)}
        ${file_wget_links_refs:+${file_wget_links_refs}(N)}
        ${file_wget_sitemap:+${file_wget_sitemap}(N)}
        ${file_wget_sitemap_tree:+${file_wget_sitemap_tree}(N)}
        ${file_wget_log:+${file_wget_log}(|.zst)(N)}
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

    if [[ -s ${file_wget_errors} ]]; then
      typeset -i wget_errors_cnt=${#${(fA)"$(< ${file_wget_errors})"}}
      sort -d -f -k2,2 -k1,1 -t $'\t' -o ${file_wget_errors}{,}
      print -- "\n\342\200\224 CHECK ${wget_errors_cnt} URL${${wget_errors_cnt:#1}:+S} IN ${(U)file_wget_errors}, WHICH MIGHT HAVE AFFECTED SPIDERING."
    fi
  }

  trap 'cleanup' INT QUIT TERM

  ( () {
      : '# The in-scope URLs belong to the same domain (cf. $subtree_only)'
      typeset -g -T -U IN_SCOPE in_scope '|'
      typeset -i line_index
      if (( line_index=${wget_opts[(I)--domains=*]} )); then
        in_scope=( ${${(s<,>)${wget_opts[${line_index}]:10}}/#/https?://} )
      else
        in_scope=( ${${${address#*//}%%/*}/#/https?://} )
      fi
    }

    { wget \
        --debug \
        ${wget_opts[@]} \
        --no-directories \
        --directory-prefix="${${TMPDIR-${XDG_RUNTIME_DIR-${HOME%/}/tmp}}%/}/wget.${project}.${RANDOM}" \
        --no-config \
        --execute robots=off \
        --input-file=- \
        --local-encoding=UTF-8 \
        --page-requisites \
        --recursive \
        --spider \
        -- \
        <<< ${(F)address} 2>&1 \
        \
          || case ${wget_error::=$?} in
               ( 1 ) wget_error+=( 'A GENERIC ERROR' ) ;;
               ( 2 ) wget_error+=( 'A PARSE ERROR' ) ;;
               ( 3 ) wget_error+=( 'A FILE I/O ERROR' ) ;;
               ( 4 ) wget_error+=( 'A NETWORK FAILURE' ) ;;
               ( 5 ) wget_error+=( 'A SSL VERIFICATION FAILURE' ) ;;
               ( 6 ) wget_error+=( 'AN USERNAME/PASSWORD AUTHENTICATION FAILURE' ) ;;
               ( 7 ) wget_error+=( 'A PROTOCOL ERROR' ) ;;
               ( 8 ) wget_error+=( 'A SERVER ISSUED AN ERROR RESPONSE' ) ;;
               ( * ) wget_error+=( 'AN UNKNOWN ERROR' ) ;;
             esac
             \
    } > ${file_wget_log} \
      > >(gawk -v IGNORECASE=1 \
               -v OFS='\t' \
               -v RS='\r?\n' \
               -v address=${${${+ADDRESS}:#1}:+${address}} \
               -v file_address=${file_address-} \
               -v file_wget_errors=${file_wget_errors} \
               -v file_wget_links=${file_wget_links} \
               -v file_wget_links_abs_refs=${file_wget_links_abs_refs} \
               -v file_wget_links_refs=${file_wget_links_refs} \
               -v file_wget_sitemap=${file_wget_sitemap} \
               -v file_wget_finish_tmp=${file_wget_finish_tmp} \
               -v in_scope="@/^(${IN_SCOPE})/" \
               -v internal_only="@/${internal_only:+^(${IN_SCOPE}|(mailto|tel):)}/" \
               -v no_parser_json=$(command -v json_pp >/dev/null)$? \
               -v no_parser_xml=$(command -v xmllint >/dev/null)$? \
               -v skip_links_abs="@/${skip_links_abs}/" \
               -v subtree_only=@/${subtree_only:+^\(${(j<|>)${${${address#*//}%/*}/#/https?://}}\)}/ \
               -v wget_opts="${${(q+)wget_opts[@]}//\\/\\\\}" '

            function percent_encode(str)
            {
              # NB: Does not work beyond the ASCII character set.
              #
              # The unsafe characters are in accordance with wget/src/url.c.
              if (str ~ /[ \{\}\|\\\^`<>%"]/) {
                if (str ~ /%[[:xdigit:]]{2}/) {
                  # Translate a percent-encoded but possibly non-conformant URL into a percent-encoded conformant one.
                  return _percent_encode(_percent_decode(str))
                } else {
                  return _percent_encode(str)
                }
              } else {
                return str
              }
            }

            function _percent_encode(_str,     char, i, ii, len, res)
            {
              for (i = 1; i <= 255; i++) {
                hex[sprintf("%c", i)] = sprintf("%%%02X", i)
              }
              len = length(_str)
              for (ii = 1; ii <= len; ii++) {
                char = substr(_str, ii, 1)
                # The safe/reserved characters are in accordance with wget/src/url.c.
                if (char ~ /[[:alnum:]\-_\.\+!~\*\047\(\);\/\?:#@&=$,\[\]]/) {
                  res = res char
                } else {
                  res = res hex[char]
                }
              }
              return res
            }

            function _percent_decode(__str,     i, res)
            {
              __str = split(__str, arr, /%[[:xdigit:]]{2}/, seps)
              res = ""
              for (i = 1; i <= __str - 1; i++) {
                res = res arr[i]
                res = res sprintf("%c", strtonum("0x" substr(seps[i], 2)))
              }
              res = res arr[i]
              return res
            }


            function print_to_term(_link, display)
            {
              if (display == "root_link") {
                printf "\r%6d\t%3d%\t\t%s\n", checked, percent, _link
              } else if (display == "child_link") {
                printf "%6s\t%3s\t\t%s%s\n", " ", " ", "\342\224\224\342\224\200>", _link
              } else if (display == "no_link") {
                printf "\r%6s\t%3d%", " ", percent
              }
            }


            function print_to_file(_link, _referer)
            {
              if (subtree_only) {
                if (_link ~ subtree_only) {
                  _print_to_file(_link, _referer)
                }
              } else if (internal_only) {
                if (_link ~ internal_only) {
                  _print_to_file(_link, _referer)
                }
              } else {
                _print_to_file(_link, _referer)
              }
            }

            function _print_to_file(__link, __referer)
            {
              # Removing duplicates with awk is memory-consuming (esp. in the case of 10^5 - 10^6 URLs), but saves on disk I/O operations.
              if (! seen_links[__link]++) {
                print(__link) > file_wget_links
              }
              print(__link, __referer) > file_wget_links_refs
            }


            function print_error_to_file(url_failed, error)
            {
              print(url_failed, error) > file_wget_errors
              # Sometimes it is useful to see the errors immediately.
              fflush(file_wget_errors)
            }


            function resolve_url(url_raw, ___referer,     url_full)
            {
              if (/^\//) {
                match(___referer, /^https?:\/\/[^\/]*/)
                url_full = (substr(___referer, RSTART, RLENGTH) url_raw)
                print_to_term(url_full, "child_link")
                print_to_file(url_full, ___referer)
              } else if (/^https?:/) {
                print_to_term(url_raw, "child_link")
                print_to_file(url_raw, ___referer)
                # Removing duplicates with awk is memory-consuming (esp. in the case of 10^5 - 10^6 URLs), but saves on disk I/O operations.
                if ((! skip_links_abs || url_raw !~ skip_links_abs) && ! seen_links_abs[url_raw, ___referer]++) {
                  print(url_raw, ___referer) > file_wget_links_abs_refs
                }
              } else {
                url_full = ((gensub(/[^\/]*$/, "", 1, ___referer)) url_raw)
                print_to_term(url_full, "child_link")
                print_to_file(url_full, ___referer)
              }
            }


            BEGIN {
              if (address) {
                print_to_file(address, "")
              } else if (file_address) {
                while ((getline < file_address) > 0) {
                  print_to_file($0, "")
                }
                close(file_address)
              }
            }

            /^Dequeuing/ {
              getline
              queued = gensub(/,$/, "", 1, $3)
            }

            /^(FINISHED )?--[0-9]{4}(-[0-9]{2}){2} [0-9]{2}(:[0-9]{2}){2}--/ {
              # Save unsuccessful in-scope requests that have not reached the "response end" message reported by Wget (part 1 of 2).
              if (f_begin && ! f_end && ! seen_err_local[referer errormsg_bg]++) {
                print_error_to_file(referer, errormsg_bg)
              }

              f_end = 0
              f_ref_in_scope = 0
              f_ref_in_scope_uniq = 0
              errormsg_bg = ""
              link = ""
              referer = ""
              response_code = ""
              delete arr
              delete hex
              delete seps

              # New round starts here.
              if (! /^FINISHED/) {
                referer = $NF

                if (referer ~ in_scope) {
                  f_ref_in_scope = 1
                  if (! seen_referer[referer]++) {
                    f_ref_in_scope_uniq = 1
                    f_begin = 1
                    checked += 1
                    percent = sprintf("%.4f", 100 - (100 * queued / (checked + queued + 0.01)))
                    if (subtree_only) {
                      if (referer ~ subtree_only) {
                        print_to_term(referer, "root_link")
                      } else {
                        print_to_term(referer, "no_link")
                      }
                    } else {
                      print_to_term(referer, "root_link")
                    }
                  }
                }

                if (! no_parser_json) {
                  if (referer ~ /\.webmanifest|manifest\.json/) {
                    cmd = "wget "\
                             wget_opts "\
                             --no-config \
                             --no-content-on-error \
                             --execute robots=off \
                             --quiet \
                             --output-document=- \
                             -- "\
                             referer "\
                             | json_pp 2>/dev/null"
                    while (cmd | getline) {
                      if (/\042src\042/) {
                        sub(/.*\042src\042[[:blank:]]*:[[:blank:]]*\042/, "", $0)
                        sub(/\042,?$/, "", $0)
                        if ($0) {
                          if (! seen_manifest[$0]++) {
                            resolve_url(percent_encode($0), referer)
                          }
                        }
                      }
                    }
                    close(cmd)
                    cmd = ""
                  }
                }

                if (! no_parser_xml) {
                  if (referer ~ /browserconfig\.xml/) {
                    # xmllint <2.9.9 outputs XPath results in one line, so we would rather only let it format, and parse everything ourselves.
                    cmd = "wget "\
                             wget_opts "\
                             --no-config \
                             --no-content-on-error \
                             --execute robots=off \
                             --quiet \
                             --output-document=- \
                             -- "\
                             referer "\
                             | xmllint \
                                 --format \
                                 - 2>/dev/null"
                    while (cmd | getline) {
                      if (/src=\042/) {
                        sub(/.*src=\042/, "", $0)
                        sub(/\042[[:blank:]]*\/>$/, "", $0)
                        if ($0) {
                          if (! seen_browserconfig[$0]++) {
                            resolve_url(percent_encode($0), referer)
                          }
                        }
                      }
                    }
                    close(cmd)
                    cmd = ""
                  }
                }
              }
            }

            # A best guess as to what error message Wget has produced.
            / error|failed|timed out|unable to resolve|(Ignoring response|No data received\.)$/ {
              errormsg_bg = $0
            }

            /^---response begin---$/, /^---response end---$/ {
              if (/^HTTP\//) {
                response_code = $2

                # Save (possibly transient) unsuccessful in-scope requests reported by a remote server (part 2 of 2).
                if (response_code ~ /^(401|400|403|408|418|429|500|502|503|504)$/ && f_ref_in_scope && ! seen_err_remote[referer response_code]++) {
                  print_error_to_file(referer, response_code)
                }
              }

              if (/^Content-Type: (text\/html|application\/xhtml\+xml)/ && response_code ~ /^(200|204|206|304)$/ && f_ref_in_scope_uniq) {
                print(referer) > file_wget_sitemap
              }

              # Upon reaching this message, we assume that the URL has successfully finished downloading.
              if (/^---response end---$/) {
                f_begin = 0
                f_end = 1
              }
            }

            /^\/.*\.tmp: merge\(\047/ {
              split($0, urls, "\047")
              if (urls[4] ~ /^(https?:|\/\/)/) {
                split(urls[2], url_parent, "/")
                sub(/\/\/www\./, "//", url_parent[3])

                split(urls[4], url_abs, "/")
                sub(/\/\/www\./, "//", url_abs[3])

                if (url_parent[3] && url_abs[3]) {
                  if (url_parent[3] == url_abs[3]) {
                    # Removing duplicates with awk is memory-consuming (esp. in the case of 10^5 - 10^6 URLs), but saves on disk I/O operations.
                    if ((! skip_links_abs || urls[4] !~ skip_links_abs) && ! seen_links_abs[urls[4], urls[2]]++) {
                      print(urls[4], urls[2]) > file_wget_links_abs_refs
                    }
                  }
                }
                delete url_abs
                delete url_parent
              }
              delete urls
            }

            /^\/.*:( merged)? link \042.*\042 doesn\047t parse\.$/ {
              sub(/.*:( merged)? link \042/, "", $0)
              sub(/\042 doesn\047t parse\.$/, "", $0)
              gsub(/ /, "%20", $0)
              if (! /^(javascript|data):/) {
                print_to_file($0, referer)
              }
            }

            /^Deciding whether to enqueue \042/ {
              link = $0
              getline
              if (! /(^Not following non-HTTPS links|is excluded\/not-included( through regex)?|does not match acc\/rej rules)\.$/) {
                sub(/^Deciding whether to enqueue \042/, "", link)
                sub(/\042\.$/, "", link)
                print_to_file(percent_encode(link), referer)
              }
            }

            /^Not following due to \047link inline\047 flag:/ {
              sub(/^Not following due to \047link inline\047 flag: /, "", $0)
              print_to_file(percent_encode($0), referer)
            }

            /^FINISHED --/, 0 {
              if (/^Downloaded:/) {
                print($1 " " $4) > file_wget_finish_tmp
              } else {
                print($0) > file_wget_finish_tmp
              }
            }'
         )

    : '# if Wget soft-failed, only show the status code, but if it hard-failed, show also a log fragment'
    if (( ${+wget_error} )); then
      wget_error[1]=( ${${wget_error[1]/#/\(code }/%/\)} )

      if [[ -e ${file_wget_finish_tmp} ]]; then
        print -- "\n--WGET SOFT-FAILED WITH ${(Oa)wget_error[@]}--" >&2
      else
        typeset wget_hard_fail
        print -n -- "\e[3m"
        tail -n 40 -- ${file_wget_log}
        print -n -- "\e[0m"
        print -- "\n--WGET FAILED WITH ${(Oa)wget_error[@]}--" >&2
      fi
    fi

    : '# if Wget exited successfully or soft-failed, show statistics'
    if (( ! ${+wget_hard_fail} )); then
      if [[ -s ${file_wget_finish_tmp} ]]; then
        print -l -- "\n$(< ${file_wget_finish_tmp})"
        print -l -- "Total links found: ${#${(fA)"$(< ${file_wget_links})"}}"
      fi

      if command -v osascript >/dev/null; then
        osascript -e "display notification \"${project}\" with title \"Wget completed\" sound name \"Submarine\""
      elif command -v notify-send >/dev/null; then
        notify-send ${project} 'Wget completed' --icon='dialog-information'
      fi
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
    'gawk,5.0.0'  'NR == 1 { print $3 }'
    'sort'        ''
    'tail'        ''
    'wget,1.21.2' 'NR == 1 { print $3 }'
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

  wget --debug --output-document='/dev/null' http://example.com 2>&1 \
    | gawk '/Debugging support not compiled in/ { exit 1 }' \
        || exit_fn "Wget should be compiled with the \"debug\" support."
}

check \
  && LC_ALL='C' main

: '# end'
