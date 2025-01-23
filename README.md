# Shell link checker
Shell script for checking broken links on a web site, based on **Wget** and **curl**. The script consists of two one-liners (sort of) to be edited _ad hoc_, copied and pasted into the terminal, and run consecutively.

Fine-tuning of Wget and curl may be necessary, such as specifying credentials, setting timeouts, including or excluding files, paths, or domains, mimicking a browser, or handling HTTP or SSL errors. Consult the respective MAN pages for options to customize the behavior.

## Features
- Link checking, including links in a web application manifest and browserconfig.xml
- Email checking
- Data collection (TITLE/META description/og:title/og:description extraction, absolute links, mailto and tel links, etc.)
- Custom term search (useful for checking for soft 404's, etc.)

![Screenshot](/broken-links.jpg)

## Prerequisites
### Necessary
|Prerequisite|Note|
|-:|:-|
|zsh|>=5.5.1<br />Modules: zsh/files, zsh/mapfile, zsh/stat|
|curl|>= 7.75.0|
|gawk|>=5.0.0|
|wget|>=1.21.2<br />Compiled with the "debug" support|
|sort||
|tail||

### Optional
|Prerequisite|Note|
|-:|:-|
|host|For checking domain MX records|
|json_pp|For parsing json files|
|osascript/<br />notify-send|For notification when the scripts have finished|
|xmllint|For parsing xml/html contents<br />libxml2 >=2.9.9|
|zstd|For compressing log files|

## Step 1
Specify your project name and URL or URL list file to check, and run:

```Shell
 : '# Gather links using Wget, v2.5.0'

main() {
  : '# START OF CUSTOMIZABLE SECTION'

  : '# Specify a project name*'
  typeset        project=''

  : '# Specify a URL or a URL list file*'
  typeset        address=''

  : '# Specify a non-null value to exclude external links (except the mailto and tel URL schemes). Mutually exclusive with $subtree_only'
  typeset  internal_only=''

  : '# Specify a non-null value to exclude links up the $address tree (a trailing slash indicates a directory). Mutually exclusive with $internal_only, but takes precedence'
  typeset   subtree_only=''

  : '# Specify a regexp (POSIX ERE, case-insensitive) to exclude links from the absolute links report'
  typeset skip_links_abs=''

  : '# Specify Wget options (except for those after the "wget" command below)'
  typeset -a    wget_opts=(
    --level='inf'
    --no-parent
  )

  : '# Specify a path for resulting files'
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

  typeset file_wget_links="${project}-wget-links.txt"
  typeset file_wget_links_abs_refs="${project}-wget-links-abs-refs.tsv"
  typeset file_wget_links_refs="${project}-wget-links-refs.tsv"
  typeset file_wget_log="${project}-wget.log"
  typeset file_wget_sitemap="${project}-wget-sitemap.txt"
  typeset file_wget_sitemap_tree="${project}-wget-sitemap-tree.txt"
  typeset file_wget_tmp==()

  () {
    if [[ -e ${file_wget_links} || \
          -e ${file_wget_links_abs_refs} || \
          -e ${file_wget_links_refs} || \
          -e ${file_wget_log} || \
          -e "${file_wget_log}.zst" || \
          -e ${file_wget_sitemap} || \
          -e ${file_wget_sitemap_tree} ]]; then
      typeset REPLY
      if read -q $'?\342\200\224'" Overwrite existing files in ${path:t2}? (y/n) "; then
        builtin rm -s -- ${file_wget_links:+${file_wget_links}(N)} \
                         ${file_wget_links_abs_refs:+${file_wget_links_abs_refs}(N)} \
                         ${file_wget_links_refs:+${file_wget_links_refs}(N)} \
                         ${file_wget_log:+${file_wget_log}(|.zst)(N)} \
                         ${file_wget_sitemap:+${file_wget_sitemap}(N)} \
                         ${file_wget_sitemap_tree:+${file_wget_sitemap_tree}(N)}
        print -l
      else
        exit_fn
      fi
    fi
  }

  cleanup() {
    () {
      typeset file
      for file in ${file_wget_links} \
                  ${file_wget_links_abs_refs} \
                  ${file_wget_links_refs} \
                  ${file_wget_sitemap}; do
        if [[ -s ${file} ]]; then
          sort -u -o ${file}{,}
        fi
      done
    }

    gawk -F '/' \
         -v file_wget_sitemap_tree=${file_wget_sitemap_tree} '
      NR == 1 { offset_start=NF }
              { offset=offset_start
                path=""

                gsub(/\//, "/1")
                if (! /\/1$/)
                  sub(/$/, "/2")

                while (offset < NF)
                  { offset++
                    path=path "|  "
                  }

                gsub(/\/1/, "/")
                sub(/\/2$/, "")

                print path "|--", $0 > file_wget_sitemap_tree
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
        ${file_wget_links:+${file_wget_links}(N)}
        ${file_wget_links_abs_refs:+${file_wget_links_abs_refs}(N)}
        ${file_wget_links_refs:+${file_wget_links_refs}(N)}
        ${file_wget_sitemap:+${file_wget_sitemap}(N)}
        ${file_wget_sitemap_tree:+${file_wget_sitemap_tree}(N)}
        ${file_wget_log:+${file_wget_log}(|.zst)(N)}
      )
      typeset -A fstat
      typeset -a match mbegin mend
      typeset MATCH MBEGIN MEND

      print -l -- "\nCREATED FILES"
      for file in ${files[@]}; do
        builtin stat -A fstat -n +size -- ${file:P}
        printf "%14s\t%s\n" ${(v)fstat:fs/%(#b)([^,])([^,](#c3)(|,*))/${match[1]},${match[2]}} \
                            ${${zstd_output:+${(k)fstat/%.zst/.zst  ${${zstd_output:s/(#m)[[:digit:].]##\%/${MATCH}}[${MBEGIN},${MEND}]}}}:-${(k)fstat}}
      done
    }
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
        --execute robots='off' \
        --input-file=- \
        --local-encoding='UTF-8' \
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
               -v file_wget_links=${file_wget_links} \
               -v file_wget_links_abs_refs=${file_wget_links_abs_refs} \
               -v file_wget_links_refs=${file_wget_links_refs} \
               -v file_wget_sitemap=${file_wget_sitemap} \
               -v file_wget_tmp=${file_wget_tmp} \
               -v in_scope="@/^(${IN_SCOPE})/" \
               -v internal_only="@/${internal_only:+^(${IN_SCOPE}|(mailto|tel):)}/" \
               -v no_parser_json=$(command -v json_pp >/dev/null)$? \
               -v no_parser_xml=$(command -v xmllint >/dev/null)$? \
               -v skip_links_abs="@/${skip_links_abs}/" \
               -v subtree_only=@/${subtree_only:+^\(${(j<|>)${${${address#*//}%/*}/#/https?://}}\)}/ \
               -v wget_opts="${${(q+)wget_opts[@]}//\\/\\\\}" '

            function percent_encoding(url) {
              # the unsafe characters (and, correspondingly, the safe/reserved ones in the _percent_encode function) are in accordance with wget/src/url.c
              if (url ~ /[\040\{\}\|\\\^`<>%"]/)
                { # translate a percent-encoded (but possibly non-conformant) URL into a percent-encoded (and conformant) one
                  if (url ~ /%[[:xdigit:]]{2}/)
                    return _percent_encode(_percent_decode(url))
                  else
                    return _percent_encode(url)
                }
              else
                return url
            }

            function _percent_decode(str,     i, res) {
              str = split(str, arr, /%[[:xdigit:]]{2}/, seps)
              res = ""
              for (i = 1; i <= str - 1; i++)
                { res = res arr[i]
                  res = res sprintf("%c", strtonum("0x" substr(seps[i], 2)))
                }
              res = res arr[i]
              return res
            }

            function _percent_encode(str,     char, i, ii, len, res) {
              for (i = 1; i <= 255; i++)
                hex[sprintf("%c", i)] = sprintf("%%%02X", i)
              len = length(str)
              for (ii = 1; ii <= len; ii++)
                { char = substr(str, ii, 1)
                  if (char ~ /[[:alnum:]\-_\.\+!~\*\047\(\);\/\?:#@&=$,\[\]]/)
                    res = res char
                  else
                    res = res hex[char]
                }
              return res
            }

            function print_to_screen(link, display) {
              if (display == "root_link")
                printf "\r%6d\t%3d%\t\t%s\n", checked, percent, link
              else if (display == "child_link")
                printf "%6s\t%3s\t\t%s%s\n", "\040", "\040", "\342\224\224\342\224\200>", link
              else if (display == "no_link")
                printf "\r%6s\t%3d%", " ", percent
            }

            function print_to_file(link, referer) {
             if (subtree_only)
                { if (link ~ subtree_only)
                    _print_to_file(link, referer)
                }
              else if (internal_only)
                { if (link ~ internal_only)
                    _print_to_file(link, referer)
                }
              else
                _print_to_file(link, referer)
            }

            function _print_to_file(link, referer) {
              print link, referer > file_wget_links_refs
              print link > file_wget_links
            }

            function construct_url(str,     url) {
              if (/^\//)
                { match(referer, /^https?:\/\/[^\/]*/)
                  url=(substr(referer, RSTART, RLENGTH) str)
                  print_to_screen(url, "child_link")
                  print_to_file(url, referer)
                }
              else if (/^https?:/)
                { print_to_screen(str, "child_link")
                  print_to_file(str, referer)
                  if ((! skip_links_abs) || (str !~ skip_links_abs))
                    print str, referer > file_wget_links_abs_refs
                }
              else
                { url=(gensub(/[^\/]*$/, "", 1, referer) str)
                  print_to_screen(url, "child_link")
                  print_to_file(url, referer)
                }
            }

            BEGIN                                                { if (address)
                                                                     print_to_file(address, "")
                                                                   else if (file_address)
                                                                     { while (( getline < file_address) > 0 )
                                                                         print_to_file($0, "")
                                                                     }
                                                                 }
            /^Dequeuing/                                         { getline
                                                                   queued=$3
                                                                 }
            /^--[0-9]{4}(-[0-9]{2}){2} [0-9]{2}(:[0-9]{2}){2}--/ { referer=$NF
  
                                                                   if (referer ~ in_scope)
                                                                     if (!seen_referer[referer]++)
                                                                       { checked+=1
                                                                         percent=sprintf("%.4f", 100 - (100 * queued / (checked + queued + 0.01)))
                                                                       
                                                                         if (subtree_only)
                                                                           { if (referer ~ subtree_only)
                                                                               print_to_screen(referer, "root_link")
                                                                             else
                                                                               print_to_screen(referer, "no_link")
                                                                           }
                                                                         else
                                                                           print_to_screen(referer, "root_link")
                                                                       }

                                                                   if (! no_parser_json)
                                                                     { if (referer ~ /\.webmanifest|manifest\.json/)
                                                                         { cmd="wget "\
                                                                                  wget_opts "\
                                                                                  --no-config \
                                                                                  --no-content-on-error \
                                                                                  --execute robots='\''off'\'' \
                                                                                  --quiet \
                                                                                  --output-document=- \
                                                                                  -- "\
                                                                                  referer "\
                                                                                  | json_pp 2>/dev/null"
                                                                           while (cmd | getline)
                                                                             { if (/\042src\042/)
                                                                                 { sub(/.*\042src\042[[:blank:]]*:[[:blank:]]*\042/, "")
                                                                                   sub(/\042,?$/, "")
                                                                                   if ($0)
                                                                                     if (!seen_manifest[$0]++)
                                                                                       construct_url(percent_encoding($0))
                                                                                 }
                                                                             }
                                                                           close(cmd)
                                                                         }
                                                                     }
                                                                   
                                                                   if (! no_parser_xml)
                                                                     { if (referer ~ /browserconfig\.xml/)
                                                                         # xmllint <2.9.9 outputs XPath results in one line, so we would rather only let it format, and parse everything ourselves
                                                                         { cmd="wget "\
                                                                                  wget_opts "\
                                                                                  --no-config \
                                                                                  --no-content-on-error \
                                                                                  --execute robots='\''off'\'' \
                                                                                  --quiet \
                                                                                  --output-document=- \
                                                                                  -- "\
                                                                                  referer "\
                                                                                  | xmllint \
                                                                                      --format \
                                                                                      - 2>/dev/null"
                                                                           while (cmd | getline)
                                                                             { if (/src=\042/)
                                                                                 { sub(/.*src=\042/, "")
                                                                                   sub(/\042[[:blank:]]*\/>$/, "")
                                                                                   if ($0)
                                                                                     if (!seen_browserconfig[$0]++)
                                                                                       construct_url(percent_encoding($0))
                                                                                 }
                                                                             }
                                                                           close(cmd)
                                                                         }
                                                                     }
                                                                 }
            /^---response begin---$/, /^---response end---$/     { if (referer ~ in_scope)
                                                                     { if (/^HTTP\//)
                                                                         response_code=$2
                                                                       if ((/^Content-Type: (text\/html|application\/xhtml\+xml)/) \
                                                                             && response_code ~ /^(200|204|206|304)$/)
                                                                         print referer > file_wget_sitemap
                                                                     }
                                                                 }
            /\.tmp: merge\(\047/                                 { split($0, urls, "\047")
                                                                   if (urls[4] ~ /^(https?:|\/\/)/)
                                                                     { split(urls[2], url_parent, "/")
                                                                       sub(/\/\/www\./, "//", url_parent[3])

                                                                       split(urls[4], url_abs, "/")
                                                                       sub(/\/\/www\./, "//", url_abs[3])

                                                                       if (url_parent[3] && url_abs[3])
                                                                         { if (url_parent[3] == url_abs[3])
                                                                           { if ((! skip_links_abs) || (urls[4] !~ skip_links_abs))
                                                                               print urls[4], urls[2] > file_wget_links_abs_refs
                                                                           }
                                                                         }
                                                                     }
                                                                 }
            /:( merged)? link \042.*\042 doesn\047t parse\.$/    { sub(/.*:( merged)? link \042/, "")
                                                                   sub(/\042 doesn\047t parse\.$/, "")
                                                                   gsub(/\040/, "%20")
                                                                   if (! /^(javascript|data):/)
                                                                     print_to_file($0, referer)
                                                                 }
            /^Deciding whether to enqueue \042/                  { link=$0
                                                                   getline
                                                                   if (! /(^Not following non-HTTPS links|is excluded\/not-included( through regex)?|does not match acc\/rej rules)\.$/)
                                                                     { sub(/^Deciding whether to enqueue \042/, "", link)
                                                                       sub(/\042\.$/, "", link)
                                                                       print_to_file(percent_encoding(link), referer)
                                                                     }
                                                                 }
            /^Not following due to \047link inline\047 flag:/    { sub(/^Not following due to \047link inline\047 flag: /, "", $0)
                                                                   print_to_file(percent_encoding($0), referer)
                                                                 }
            /^FINISHED --/, 0                                    { if (/^Downloaded:/)
                                                                     print $1 "\040" $4 > file_wget_tmp
                                                                   else
                                                                     print $0 > file_wget_tmp
                                                                 }'
         )

    : 'if Wget soft-failed, only show the status code, but if it hard-failed, show also a log fragment'
    if (( ${+wget_error} )); then
      wget_error[1]=( ${${wget_error[1]/#/\(code }/%/\)} )

      if [[ -e ${file_wget_tmp} ]]; then
        print -- "\n--WGET SOFT-FAILED WITH ${(Oa)wget_error[@]}--" >&2
      else
        typeset wget_hard_fail
        print -n -- "\e[3m"
        tail -n 40 -- ${file_wget_log}
        print -n -- "\e[0m"
        print -- "\n--WGET FAILED WITH ${(Oa)wget_error[@]}--" >&2
      fi
    fi

    : 'if Wget exited successfully or soft-failed, show statistics'
    if (( ! ${+wget_hard_fail} )); then
      if [[ -s ${file_wget_tmp} ]]; then
        print -l -- "\n$(< ${file_wget_tmp})"
        print -- 'Total links found:' ${#${(f)"$(sort -u ${file_wget_links})"}}
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


: '# prerequisites check'
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
```

#### Resulting files:
- `${project}-wget-links.txt` - list of all links found.
- `${project}-wget-links-abs-refs.tsv` - list of absolute links found.
- `${project}-wget-links-refs.tsv` - list of links and their referers.
- `${project}-wget-sitemap.txt` - list of html links found.
- `${project}-wget-sitemap-tree.txt` - list of html links as a tree.
- `${project}-wget.log(.zst)` - Wget log for debugging purposes.


## Step 2
Specify the same project name as above, and run:

```Shell
 : '# Check links using curl, v2.5.0'

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

  : '# Specify a path for resulting files'
  typeset -h          path=~

  : '# END OF CUSTOMIZABLE SECTION'


  true ${project:?Specify a project name.}

  set -o LOCAL_TRAPS \
      -o WARN_CREATE_GLOBAL \
      +o UNSET

  zmodload -F zsh/files b:mv b:rm
  zmodload zsh/mapfile

  SECONDS=0

  true ${path::=${path%/}/${project}}
  cd -q ${path} \
    && trap 'cd -q ~-' EXIT

  typeset -a file_wget_links=( ${(f)mapfile[${project}-wget-links.txt]-} )
  typeset file_wget_links_refs=$( () { print -- ${1-} } "${project}-wget-links-refs.tsv"(N) )
  typeset file_wget_log=$( () { print -- ${1-} } "${project}-wget.log"(|.zst)(N) )
  typeset -a file_wget_sitemap=( ${(fL)mapfile[${project}-wget-sitemap.txt]-} )
  typeset file_broken_links="${project}-broken-links-%D{%F-%H%M}.tsv"
  typeset file_curl_log="${project}-curl.log"
  typeset file_curl_summary="${project}-curl-summary.tsv"
  typeset file_curl_tmp==()

  true "${file_wget_links:?File missing.}"
  true ${file_wget_links_refs:?File missing.}
  true ${file_wget_log:?File missing.}
  true "${file_wget_sitemap:?File missing.}"

  () {
    if [[ -e ${file_curl_log} || \
          -e "${file_curl_log}.zst" || \
          -e ${file_curl_summary} ]]; then
      typeset REPLY
      if read -q $'?\342\200\224'" Overwrite existing files in ${path:t2}? (y/n) "; then
        builtin rm -s -- ${file_curl_log:+${file_curl_log}(|.zst)(N)} \
                         ${file_curl_summary:+${file_curl_summary}(N)}
        print -l
      else
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
      typeset -a match mbegin mend
      typeset MATCH MBEGIN MEND

      print -l -- "\nCREATED FILES"
      for file in ${files[@]}; do
        builtin stat -A fstat -n +size -- ${file:P}
        printf "%14s\t%s\n" ${(v)fstat:fs/%(#b)([^,])([^,](#c3)(|,*))/${match[1]},${match[2]}} \
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
             -v file_curl_tmp=${file_curl_tmp} \
             -v links_total=${#file_wget_links[@]} \
             -v no_parser_mx=$(command -v host >/dev/null)$? \
             -v no_parser_xml=$(command -v xmllint >/dev/null)$? '
          BEGIN                                  { print "URL",
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
                                                         custom_query_5 > file_curl_summary
                                                 }
          /^< Content-Length:/                   { if ($3 != 0) size=sprintf("%.f", $3/1024)
                                                   if (size == 0) size=1
                                                 }
          /^< Content-Type:/                     { split($0, a_ctype, /[:;=]/)
                                                   type=a_ctype[2]
                                                   gsub(/^\040+|\040+$/, "", type)

                                                   charset=a_ctype[4]
                                                   gsub(/^\040+|\040+$/, "", charset)
                                                   if (! charset) charset="UTF-8"
                                                 }
          /^< Location:/                         { redirect=$3 }
          /^Warning: Problem : (timeout|connection refused|HTTP error)\./ \
                                                 { n=1         }
          /<TITLE[^>]*>/, /<\/TITLE>/            { mult_title++
                                                   if (mult_title > 1 && ! n)
                                                     title="MULTIPLE TITLE"
                                                   else
                                                     { if (! no_parser_xml)
                                                         { gsub(/\047/, "\047\\\047\047")
                                                           sub(/<TITLE/, "<meta http-equiv='\''Content-Type'\'' content='\''charset=" charset "'\'' />&")
                                                           cmd="xmllint \
                                                                  --html \
                                                                  --xpath '\''//title'\'' \
                                                                  - 2>/dev/null <<< '\''"$0"'\''"; \
                                                           cmd | getline title
                                                           close(cmd)

                                                           gsub(/^<TITLE[^>]*>|<\/TITLE>$/, "", title)
                                                           gsub(/^[[:blank:]]+|[[:blank:]]+$/, "", title)
                                                           if (! title) title="EMPTY TITLE"
                                                         }
                                                       else
                                                         if (! title) title="No xmllint installed"
                                                     }
                                                 }
          /<META.*og:title/, />/                 { mult_og_title++
                                                   if (mult_og_title > 1)
                                                     og_title="MULTIPLE OG:TITLE"
                                                   else
                                                     { if (! no_parser_xml)
                                                         { gsub(/\047/, "\047\\\047\047")
                                                           sub(/<META/, "<meta http-equiv='\''Content-Type'\'' content='\''charset=" charset "'\'' />&")
                                                           cmd="xmllint \
                                                                  --html \
                                                                  --xpath '\''string(//meta[@property=\"og:title\"]/@content)'\'' \
                                                                  - 2>/dev/null <<< '\''"$0"'\''"; \
                                                           cmd | getline og_title
                                                           close(cmd)
                                                         }
                                                       else
                                                         if (! og_title) og_title="No xmllint installed"
                                                     }
                                                 }
          /<META.*og:description/, />/           { mult_og_desc++
                                                   if (mult_og_desc > 1)
                                                     og_desc="MULTIPLE OG:DESCRIPTION"
                                                   else
                                                     { if (! no_parser_xml)
                                                         { gsub(/\047/, "\047\\\047\047")
                                                           sub(/<META/, "<meta http-equiv='\''Content-Type'\'' content='\''charset=" charset "'\'' />&")
                                                           cmd="xmllint \
                                                                  --html \
                                                                  --xpath '\''string(//meta[@property=\"og:description\"]/@content)'\'' \
                                                                  - 2>/dev/null <<< '\''"$0"'\''"; \
                                                           cmd | getline og_desc
                                                           close(cmd)
                                                         }
                                                       else
                                                         if (! og_desc) og_desc="No xmllint installed"
                                                     }
                                                 }
          /<META.*name=\042description\042/, />/ { mult_desc++
                                                   if (mult_desc > 1)
                                                     desc="MULTIPLE DESCRIPTION"
                                                   else
                                                     { if (! no_parser_xml)
                                                         { gsub(/\047/, "\047\\\047\047")
                                                           sub(/<META/, "<meta http-equiv='\''Content-Type'\'' content='\''charset=" charset "'\'' />&")
                                                           cmd="xmllint \
                                                                  --html \
                                                                  --xpath '\''string(//meta[@name=\"description\"]/@content)'\'' \
                                                                  - 2>/dev/null <<< '\''"$0"'\''"; \
                                                           cmd | getline desc
                                                           close(cmd)
                                                         }
                                                       else
                                                         if (! desc) desc="No xmllint installed"
                                                     }
                                                 }
          custom_query_1 != "CUSTOM QUERY"       { if ($0 ~ custom_query_1) custom_match_1="\342\234\223" }
          custom_query_2 != "CUSTOM QUERY"       { if ($0 ~ custom_query_2) custom_match_2="\342\234\223" }
          custom_query_3 != "CUSTOM QUERY"       { if ($0 ~ custom_query_3) custom_match_3="\342\234\223" }
          custom_query_4 != "CUSTOM QUERY"       { if ($0 ~ custom_query_4) custom_match_4="\342\234\223" }
          custom_query_5 != "CUSTOM QUERY"       { if ($0 ~ custom_query_5) custom_match_5="\342\234\223" }
          /^out_errormsg:/                       { if ($2 != 0) errormsg=substr($0, 15)                   }
          /^out_num_redirects:/                  { if ($2 != 0) num_redirects=$2                          }
          /^out_response_code:/                  { response_code=$2                                       }
          /^out_size_header:/                    { if ($2 != 0) downloaded+=$2                            }
          /^out_size_download:/                  { if ($2 != 0) downloaded+=$2                            }
          /^out_time_total:/                     { if ($2 != 0) time_total=sprintf("%.2fs", $2)           }
          /^out_full_download$/                  { if (! title && ! errormsg) title="NO TITLE"            }
          /^out_url:/                            { f=1

                                                   url=$2

                                                   checked+=1
                                                   if (! time_total) time_total=" --"
                                                     printf "%6d%s%-6d\t%s\t%s\n", checked, "/", links_total, time_total, url

                                                   if (url !~ /^https?:/ && url ~ /^([[:alnum:]+.-]+):/)
                                                     { if (url ~ /^mailto:/)
                                                         { if (url ~ /[,;]/ && url ~ /(@.+){2,}/)
                                                             code="Mailbox list not supported"
                                                           else if (url ~ /^mailto:(%20)*[[:alnum:].!#$%&\047*+/=?^_`{|}~-]+@[[:alnum:].-]+\.[[:alpha:]]{2,64}(%20)*(\?.*)?$/)
                                                             { if (! no_parser_mx)
                                                                 { cmd="zsh -c '\''host -t MX ${${${${:-$(<<<"url")}#*@}%%\\?*}//(%20)/}'\''"
                                                                   cmd | getline mx_check
                                                                   close(cmd)
                                                                   if (mx_check ~ /mail is handled by .{4,}/)
                                                                     code="MX found"
                                                                   else
                                                                     code=mx_check
                                                                 }
                                                               else
                                                                 code="No Host utility installed"
                                                             }
                                                           else
                                                             code="Incorrect email syntax"
                                                         }
                                                       else
                                                         code="Custom URL scheme"
                                                     }
                                                   else if (response_code != "000")
                                                     code=response_code
                                                   else if (errormsg)
                                                     code=errormsg

                                                   print url,
                                                         code,
                                                         type,
                                                         size,
                                                         redirect,
                                                         num_redirects,
                                                         title,
                                                         og_title,
                                                         og_desc,
                                                         desc,
                                                         custom_match_1,
                                                         custom_match_2,
                                                         custom_match_3,
                                                         custom_match_4,
                                                         custom_match_5 > file_curl_summary
                                                 }
          f                                      { code=""
                                                   custom_match_1=""
                                                   custom_match_2=""
                                                   custom_match_3=""
                                                   custom_match_4=""
                                                   custom_match_5=""
                                                   desc=""
                                                   errormsg=""
                                                   mult_desc=""
                                                   mult_og_desc=""
                                                   mult_og_title=""
                                                   mult_title=""
                                                   num_redirects=""
                                                   og_desc=""
                                                   og_title=""
                                                   redirect=""
                                                   response_code=""
                                                   size=""
                                                   time_total=""
                                                   title=""
                                                   type=""
                                                   f=0
                                                   n=0
                                                 }
          END                                    { split("B,K,M,G", unit, ",")
                                                   rank=int(log(downloaded)/log(1024))
                                                   printf "%.1f%s\n", downloaded/(1024**rank), unit[rank+1] > file_curl_tmp
                                                 }' \
      && sort_file_summary \
      && { true ${file_broken_links::=${(%)file_broken_links}}
           gawk -v FS='\t' \
                -v OFS='\t' \
                -v file_broken_links=${file_broken_links} \
                -v skip_code="@/^(MX found|Custom URL scheme|200${skip_code:+|${skip_code}})/" '
             NR == FNR \
               && $2 !~ skip_code { count+=1
                                    if (count == 1)
                                      { header="E R R O R S" OFS
                                        subheader=$1 OFS $2
                                      }
                                    else
                                      { if (count == 2)
                                          print header RT subheader > file_broken_links
                                        print $1, $2 > file_broken_links
                                        seen[$1]++
                                        next
                                      }
                                  }
             FNR == 1             { if (count > 1)
                                      { print OFS, RT \
                                              "L I N K S", RT \
                                              "BROKEN LINK", "REFERER" > file_broken_links
                                      }
                                  }
             $1 in seen           { print $1, $2 > file_broken_links }' ${file_curl_summary} ${file_wget_links_refs} \
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

           print -l -- "\nDownloaded: $(< ${file_curl_tmp})"
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


: '# prerequisites check'
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
```

#### Resulting files:
- `${project}-broken-links-DD-MM-YYYY-HHSS.tsv` - list of links with HTTP error codes and referers (see the image above).
- `${project}-curl-summary.tsv` - list of all links with other information.
- `${project}-curl.log(.zst)` - curl log for debugging purposes.

## Caveats
|Caveat|Note|
|-:|:-|
|`BASE`|If a web page contains the BASE tag, the referers in the `${project}-wget-links-abs-refs.tsv` file will be incorrect.|
|`LINK, META, TITLE`|The tag's content spanned over multiple lines can erroneously be reported as MULTIPLE <...>.|
|`--execute robots='off'`|Use the `--reject-regex` Wget option to exclude URLs, not this one.|
|Mailbox list|Checking of mailbox lists is not supported|
|Redirect|The URLs excluded via the `--reject-regex` Wget option will still appear in the link list if they are a redirect target.

## Version history
#### v.2.5.0 (20250123)
- Backward incompatibility: the file names are changed
- Added a check for minimum zsh version and availability of zsh modules
- Broader detection of custom URL schemes, the tel and callto schemes are no longer singled out, nor are the tel links included in the broken links report
- Fixed a bug when a wrong URL scheme was interpreted as the userinfo URL subcomponent (as "email:someone@domain.tld" instead of "mailto:someone@domain.tld")
- Fixed a bug when the start-of-string regex anchor was not correctly applied to the entire $subtree_only array
- Fixed a bug when exiting a script would close the current interactive shell
- Fixed a bug when empty URL list file triggered creation of the $address_file variable
- Added the "not supported" message for mailbox lists
- No attempt is made to read the manifest and browserconfig.xml files if they are missing
- Error messages when parsing the manifest and browserconfig.xml files are redirected to /dev/null
- Error messages for $file_wget_sitemap_tree are redirected to /dev/null
- Fixed the incorrect "Wget completed" message attribution for the "notify-send" command in the script 2
- Naming and messages/dialogs phrasing are more semantic, consistent, and clear
- Multiple code changes and improvements

#### v.2.4.2 (20240709)
- The sitemap tree is now generated by gawk (instead of by the tree utility).
  
#### v.2.4.1 (20240512)
- Added $XDG_RUNTIME_DIR to the list of temporary files locations.
- Fixed a race condition where the log content was displayed when Wget soft-failed (instead of only when hard-failed).
- Fixed a bug when URLs from an URLs list file were not added to the Wget result files other than ${project}-wget-links-and-refs.tsv.

#### v.2.4.0 (20240412):
- Added reading URLs from a file
- Added sitemap tree generation
- Shell alert on script completion changed to the system notification (Linux, MacOS)
- Date of the $file_broken_links file is taken at the end of the process, not at the beginning (useful if checking takes a day or a week)
- If the $subtree_only option is enabled, only relevant links are displayed
- The $subtree_only option now works correctly with URLs with or without trailing slashes.
- Improved error reporting
- Custom options do not overwrite the required ones
- Additional checks that all required files are present
- Single quotes in TITLE/og:title/description/og:description are unescaped
- Removed dummy curl --user foo:bar option
- Fixed "fatal error: out of heap memory" when counting the number of links using shell substitutions
- Fixed sorting of curl result files
- Fixed usage of --level Wget option and moved it to custom options block
- Fixed a bug when "NO TITLE" was reported due to curl's non-"HTTP error" problem
- Fixed a bug when the compressed log file was not overwritten
- Some speedup improvements with "mapfile" instead of input redirection
- Removed external dependencies mkdir, rm, mv in favor of the built-in ones
- Code modifications

#### v.2.3.3
- Added the callto and consultantplus link schemes
- Fixed a security issue with sending credentials with third-party requests
- Fixed a bug when HTTP links were included in the reports with the --https-only Wget option on
- Moved the --no-parent and --ignore-case Wget options to the customizable options block
- The log file is compressed by default (if zstd is present)
- Some minor code changes

#### v.2.3.2
- Modified the custom search feature to support separate queries
- The market: URL scheme excluded from the check
- Some modifications to the in-scope URL definition

#### v2.3.1
- The ${project}-curl-links.tsv file renamed to ${project}-curl-summary.tsv
- The existing $file_broken_links files do not trigger the "Overwrite existing files?" dialog
- The previous (or empty) files are removed upon subsequent script runs, not overwritten
- Some minor code changes

#### v2.3.0
- Added: if username and password were provided in the script 1, the script 2 tries to use them.
- Changed: the timestamp, which is appended to the $file_broken_links filename, now includes hours and minutes. There is also a dialog to compress the file.
- Changed: the curl output is set to verbose by default.
- Fixed a bug where some URLs were skipped when checking for empty TITLE.
- Fixed a bug where $file_wget_links_abs_refs was not reset.
- Fixed a bug where a parameter substitution was applied to a missing $TMPDIR.
- Fixed a bug where a non-root $folder was not created.
- Fixed a bug where some shell configurations reported as "/bin/zsh" were not accepted as a valid prerequisite.
- Some minor code changes.

#### v2.2.0
- The missing TITLE tag is reported.
- The Wget --exclude-domains option is not to be used (more info: it produces the same "The domain was not accepted" log message as the --include-domains option does, which we can not differentiate, and the latter is more important for us.)
- Fixed a bug when an URLs was not correctly converted to lowercase
- Fixed a bug with a concurrent execution of the Wget script when temporary files of the one process were read by the other.
- Fixed a bug with the "#" symbol being percent encoded.
- The wc, and numfmt utilities are no longer needed, and the du, and xmllint utilities are optional
- Small code changes

#### v2.1.1
- Added a dialogue if existing files should be overwritten in case of a repeated script run
- Optional dependencies, if absent, are not attempted to run
- Allowed characters for the local part of an email are extended according to RFC 5322
- The unsafe: URL scheme is excluded from the internal_only scope
- Fixed a bug when the --exclude-directories, --exclude-domains, and --reject Wget options were not respected
- Fixed a bug when the webmanifest and browserconfig files were not parsed correctly
- Fixed a bug when a link and a referer were not both percent-encoded. We let Wget encode the latter and do the like encoding for the former
- Some minor checks, code changes and clarifications on how to specify custom options

#### v2.1.0
- Disallowed URLs should be excluded manually with the reject-regex option, as Wget considers the robots.txt check expensive and stores these URLs in a blacklist, which leads to an inconsistent log reporting (see src/recur.c)
- Links with the "unsafe:" prefix (which is, for example, set by Angular) are not excluded when $internal_only is on
- Fixed the "zsh: invalid subscript" error caused by some symbols (for example, a comma) in an URL
- Fixed incorrect wall clock time reporting for checks of the duration of more than 24 hours
- $file_wget_tmp is reused to check if Wget has finished

#### v2.0.0
- META description is included in the report
- Links in webmanifest/browserconfig files are extracted and added to the report
- No requirement to regex type supported by Wget, any would do
- Wget/curl options and the script's ones are separated
- Prerequisites are checked before running the script
- Massive code rewriting

#### v1.12.0
- Added: the scripts can be stopped without losing the results accumulated up to that moment
- Added: necessary fields are checked before the start for being non-empty
- Fixed: $excl_abs_links is operative again
- Fixed: Errors are redirected to stderr
- Fewer external calls and other optimizations

#### v1.11.1
- Fixed a bug with the included domains option not being operative
- Fixed a bug with the multiple TITLE reported due to the HTTP error pages' TITLE being counted
- Fixed a bug with the empty $file_wget_links_abs_refs and $file_curl_links files not being removed
- Fixed: excluded URL's are also excluded from the $file_wget_links_refs file
- Changed: vertical bar instead of comma as an alternation symbol in options
- Added the information on how much has been downloaded after the step 2 has finished
- Minor code changes

#### v1.11.0
- Removed &amp;quot; support
- Added auth section
- Re-added the libpcre requirement
- Modified: javascript: and data: URL are excluded from the reports
- Modified: absolute links file renamed and stripped of headers
- Modified: no trying to guess tel: URL validity; these are all listed for hand-checking
- Fixed: the "open" command is checked for existence before invoking
- Fixed: better handling of non-ASCII URLs
- Fixed: removed unnecessary output to stdout
- Multiple performance optimizations

#### v1.10.1
- Fixed incorrect parameter substitution

#### v1.10
- Added a custom search capability
- Added reporting of the tel: links
- Removed requirement of libpcre support for wget and grep
- Removed the dialog whether to compress curl log file
- Fixed a bug when /tmp directory might not be created due to the lack of access rights
- Fixed a bug when URLs containing special symbols were not handled correctly by grep
- Fixed a bug when TITLE/og:* containing an unpaired single quote were not parsed correctly by awk
- Fixed a bug when TITLE's content was stripped of enclosed tags
- Some unnecessary separate processes were removed in favor of shell builtins
- Minor code improvements and tidying

#### v1.9
- Added absolute links reporting
- Added multiple TITLE/og:title/og:description reporting
- Some wget/curl options can be specified in the script's configuration part
- Fixed handling of the URLs containing spaces or non-ASCII symbols
- Fixed handling of email addresses containing spaces or parameters
- Fixed incorrect reporting of 100% progress during link check
- Fixed incorrect time display when checking email addresses
- Fixed (somewhat hackish) incorrect encoding when parsing a website's content with xmllint
- Fixed displaying the last line of the URL list intermingled with the finishing information in the terminal
- Minor code improvements

#### v1.8.1
- Fixed a typo

#### v1.8
- Email addresses are harvested and checked for validity (against a regexp and by MX record)
- TITLE, og:title, and og:description are included in the report
- $internal_only behavior is redefined (harvest all URLs within a domain, except external ones), and $subtree_only (harvest only down the starting directory) added
- Dialog is implemented whether the resulting files should be compressed
- Fixed a bug when sitemap generation incorrectly included non-html addresses
- Fixed a bug when the starting URL was missing in the reports
- Minor code improvements

#### v1.7
- Added option to exclude external links
- Added option to exclude entries in the broken links report by HTTP code
- During link gathering, percentage of checked/pending links is shown
- Sitemap generation is now based on Content-Type
- Fixed truncating URLs with spaces
- Fixed Content-Length incorrectly reported as zero
- The broken links report file is not created when there were no broken links

#### v1.6.2
- As the resulting log files may get quite large and usually of not much use, only the compressed version is kept after the checking has finished (ZStandard performed best in terms of speed, compression ratio and CPU/memory consumption, but can be changed to any other library of choice)
- Some small optimizations and bug fixes

#### v1.6.1
- Fixed incorrect error reporting

#### v1.6.0
- Added a workaround for escaped quotes in HTML [https://stackoverflow.com/questions/51368208/angularjs-ng-style-quot-issue](https://stackoverflow.com/questions/51368208/angularjs-ng-style-quot-issue)
- Added a workaround in a case when Wget finishes seemingly normally, but with an error code
- Bandwidth is counted correctly when response(s) do(es) not contain the Length value

#### v1.5.0
- Bandwidth consumed by Wget is shown 
- Bug fixes and optimizations

#### v1.4.0
- Links being processed are numbered and the connection time is shown to get the idea of how the things are going, as well as the elapsed time
- Sitemap generation
- If Wget exited with an error, the debug information is shown
- The number of redirects is recorded

#### v1.3.0
- Suspend/resume support (Ctrl+Z)
- URLs excluded from the Wget link harvesting are also excluded from the curl checking (to avoid BRE/ERE/etc. mismatching/incompatibility between chained Wget and grep, PCRE is recommended)

#### v1.2.0
- the three scripts are combined into two
- added more statictics

#### v1.1.0
- The URLs the script is working on are now shown in the terminal
- Wget statistics upon finishing the retrieval is moved from the file into the terminal
- Wget log file is no longer compressed to keep it readable in case of script's premature exit

#### v1.0.0
Initial release
