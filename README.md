# Shell link checker
Shell script for checking broken links on a web site, based on **Wget** and **curl**. The script consists of two one-liners (sort of) to be edited _ad hoc_, copied and pasted into the terminal, and run consecutively.

Fine-tuning of Wget and curl may be necessary, such as specifying credentials, setting timeouts, including or excluding files, paths, or domains, mimicking a browser, or handling HTTP or SSL errors. Consult the respective MAN pages for options to customize the behavior.

## Features
- Link checking, including links in the webmanifest/browserconfig files
- Email checking
- Data collection (TITLE/META description/og:title/og:description extraction; absolute links; mailto and tel links; etc.)
- Custom term search (useful for checking for soft 404's, etc.)

![Screenshot](/broken-links.jpg)

## Prerequisites

|Prerequisite|Note|
|-:|:-|
|zsh||
|awk|GNU|
|curl|>= 7.75.0|
|wget|compiled with the "debug" support|
|shell utilities|mkdir, mv, rm, sort, tail|
|du|optional|
|host|optional, for checking email MX records|
|json_pp|optional, for parsing json files|
|open|optional|
|xmllint|optional, for parsing xml/html contents|
|zstd|optional, for compressing log files|

## Step 1
Specify your project name and the URL to check, and run:

```Shell
 : '# Gather links using Wget, v2.3.3'

function main() {

  : '# specify the project name*'
  local         project=''

  : '# specify the URL to check*'
  local         address=''

  : '# specify non-empty value to exclude external (except mailto, tel, and callto) links from the results. Mutually exclusive with $subtree_only'
  local   internal_only=''

  : '# specify non-empty value to exclude any links up the $address tree (ending with a trailing slash) from the results. Mutually exclusive with $internal_only, but takes precedence'
  local    subtree_only=''

  : '# specify a regexp (POSIX ERE) to exclude links from the absolute links check'
  local  excl_links_abs=''

  : '# specify Wget options (except those after the "wget" command below)'
  local -a    wget_opts=(
      --no-config
      --no-parent
      --ignore-case
      --local-encoding='UTF-8'
    )

  : '# specify path for the resulting files'
  local          folder="${HOME}/${project}"


  test -z "${${address:?Specify the URL to check}:/*/}"
  test -z "${${project:?Specify the project name}:/*/}"

  setopt   LOCAL_TRAPS \
           WARN_CREATE_GLOBAL
  unsetopt UNSET

  if [[ ! -d ${folder} ]]; then
    mkdir -p "${folder}"
  fi

  local file_wget_links="${folder}/${project}-wget-links.txt"
  local file_wget_links_abs_refs="${folder}/${project}-wget-links-abs-and-refs.tsv"
  local file_wget_links_refs="${folder}/${project}-wget-links-and-refs.tsv"
  local file_wget_log="${folder}/${project}-wget.log"
  local file_wget_sitemap="${folder}/${project}-wget-sitemap.txt"
  local file_wget_error="${${TMPDIR-"${HOME}/tmp"}%/}/wget_failed_${RANDOM}"
  local file_wget_tmp="${${TMPDIR-"${HOME}/tmp"}%/}/wget_tmp_${RANDOM}"

  if [[ -a ${file_wget_links} || \
        -a ${file_wget_links_abs_refs} || \
        -a ${file_wget_links_refs} || \
        -a ${file_wget_log} || \
        -a ${file_wget_sitemap} ]]; then
    local REPLY
    if read -q '?Overwrite existing files? (y/n)'; then
      rm -- "${folder}/${project}-wget"*
      print -l
    else
      return 1
    fi
  fi

  local -l in_scope
  local -i line_index
  if (( line_index=${wget_opts[(I)--domains=*]} )); then
    in_scope="https?://(${${wget_opts[${line_index}]:10}//,/|})"
  else
    in_scope="https?://${${address#*//}%%/*}"
  fi

  function cleanup() {
    local file
    for file in "${file_wget_links}" \
                "${file_wget_links_abs_refs}" \
                "${file_wget_links_refs}" \
                "${file_wget_sitemap}"; do
      if [[ -s ${file} ]]; then
        sort -u -o "${file}"{,}
      fi
    done

    rm -f -- "${file_wget_error}" "${file_wget_tmp}"

    if command -v zstd >/dev/null; then
      local REPLY
      if ! read -t 15 -q $'?\nKeep the log file uncompressed? (y/N)'; then
        zstd --quiet --rm --force -- "${file_wget_log}"
      fi
    fi
  }

  trap cleanup INT QUIT TERM

  ( { wget \
        --debug \
        --no-directories \
        --directory-prefix="${${TMPDIR-"${HOME}/tmp"}%/}/wget.${project}.${RANDOM}" \
        --execute robots='off' \
        --level='inf' \
        --page-requisites \
        --recursive \
        --spider \
        "${wget_opts[@]}" \
        "${address}" 2>&1 \
      \
        || { local -i error_code=$?
             case "${error_code:-}" in
               1) error_name='A GENERIC ERROR' ;;
               2) error_name='A PARSE ERROR' ;;
               3) error_name='A FILE I/O ERROR' ;;
               4) error_name='A NETWORK FAILURE' ;;
               5) error_name='A SSL VERIFICATION FAILURE' ;;
               6) error_name='AN USERNAME/PASSWORD AUTHENTICATION FAILURE' ;;
               7) error_name='A PROTOCOL ERROR' ;;
               8) error_name='A SERVER ISSUED AN ERROR RESPONSE' ;;
               *) error_name='AN UNKNOWN ERROR' ;;
             esac
             if [[ -a ${file_wget_tmp} ]]; then
               print -- "\n--WGET SOFT-FAILED WITH ${error_name}${error_code:+" (code ${error_code})"}--" >&2
             else
               true > "${file_wget_error}"
               { print -n -- "\e[3m"
                 tail -n 40 -- "${file_wget_log}"
                 print -n -- "\e[0m"
                 print -l "\n--WGET FAILED WITH ${error_name} (code ${error_code})--" "Some last log entries are shown above\n"
               } >&2
             fi
           }
           \
    } > "${file_wget_log}" \
      \
      > >(gawk -v RS='\r?\n' \
               -v OFS='\t' \
               -v IGNORECASE=1 \
               -v address="${address}" \
               -v excl_links_abs="@/${excl_links_abs:+"${excl_links_abs}"}/" \
               -v file_wget_links="${file_wget_links}" \
               -v file_wget_links_abs_refs="${file_wget_links_abs_refs}" \
               -v file_wget_links_refs="${file_wget_links_refs}" \
               -v file_wget_sitemap="${file_wget_sitemap}" \
               -v file_wget_tmp="${file_wget_tmp}" \
               -v in_scope="@/^${in_scope}/" \
               -v internal_only="@/${internal_only:+"^(${in_scope}|(mailto|tel|callto):)"}/" \
               -v no_parser_json="$(command -v json_pp >/dev/null)$?" \
               -v no_parser_xml="$(command -v xmllint >/dev/null)$?" \
               -v subtree_only="@/${subtree_only:+"^${address}"}/" \
               -v wget_opts="$(print -r -- ${(q+)wget_opts[*]//\\/\\\\})" '

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
                printf "%6d\t%3d%\t\t%s\n", checked, percent, link
              else if (display == "child_link")
                printf "%6s\t%3s\t\t%s%s\n", "\040", "\040", "\342\224\224\342\224\200>", link
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
              else if (/^https?/)
                { print_to_screen(str, "child_link")
                  print_to_file(str, referer)
                  if ((! excl_links_abs) || (str !~ excl_links_abs))
                    print str, referer > file_wget_links_abs_refs
                }
              else
                { url=(gensub(/[^\/]*$/, "", 1, referer) str)
                  print_to_screen(url, "child_link")
                  print_to_file(url, referer)
                }
            }

            BEGIN                                                { print_to_file(address, "") }
            /^Dequeuing/                                         { getline
                                                                   queued=$3
                                                                 }
            /^--[0-9]{4}(-[0-9]{2}){2} [0-9]{2}(:[0-9]{2}){2}--/ { referer=$NF
  
                                                                   if (referer ~ in_scope \
                                                                         && !seen[referer]++)
                                                                     { checked+=1
                                                                       percent=sprintf("%.4f", 100 - (100 * queued / (checked + queued + 0.01)))
                                                                       print_to_screen(referer, "root_link")
                                                                     }

                                                                   if (! no_parser_json)
                                                                     { if (referer ~ /\.webmanifest|manifest\.json/)
                                                                         { cmd="wget "\
                                                                                  wget_opts "\
                                                                                  --quiet \
                                                                                  --output-document - "\
                                                                                  referer "\
                                                                                    | json_pp"
                                                                           while (cmd | getline)
                                                                             { if (/\042src\042/)
                                                                                 { sub(/.*\042src\042[[:blank:]]*:[[:blank:]]*\042/, "")
                                                                                   sub(/\042,?$/, "")
                                                                                   if ($0)
                                                                                     construct_url(percent_encoding($0))
                                                                                 }
                                                                             }
                                                                           close(cmd)
                                                                         }
                                                                     }
                                                                   
                                                                   if (! no_parser_xml)
                                                                     { if (referer ~ /browserconfig\.xml/)
                                                                         { # xmllint <2.9.9 outputs XPath results in one line, so we would rather only let it format, and parse everything ourselves
                                                                           cmd="wget "\
                                                                                  wget_opts "\
                                                                                  --quiet \
                                                                                  --output-document - "\
                                                                                  referer "\
                                                                                    | xmllint \
                                                                                        --format \
                                                                                        - "
                                                                           while (cmd | getline)
                                                                             { if (/src=\042/)
                                                                                 { sub(/.*src=\042/, "")
                                                                                   sub(/\042[[:blank:]]*\/>$/, "")
                                                                                   if ($0)
                                                                                     construct_url(percent_encoding($0))
                                                                                 }
                                                                             }
                                                                           close(cmd)
                                                                         }
                                                                     }
                                                                 }
            /^---response begin---/, /^---response end---/       { if (referer ~ in_scope)
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
                                                                           { if ((! excl_links_abs) || (urls[4] !~ excl_links_abs))
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
            /^FINISHED --/, 0                                    { if (/^Downloaded:/)
                                                                     print $1 "\040" $4 > file_wget_tmp
                                                                   else
                                                                     print $0 > file_wget_tmp
                                                                 }'
         )

    : 'if Wget did not hard-fail, show the stats'
    if [[ ! -a ${file_wget_error} ]]; then
      <<-EOF
	
	$(< "${file_wget_tmp}")
	Total links found: $(print -n -- ${#${(u)$(< "${file_wget_links}")}})

	CREATED FILES
	$(local -a files=(
	    "${file_wget_links}"
	    "${file_wget_links_abs_refs}"
	    "${file_wget_links_refs}"
	    "${file_wget_sitemap}"
	    "${file_wget_log}"
	  )
	  if command -v du >/dev/null; then
	    du -h -- "${files[@]}" 2>/dev/null
	  else
	    print -l -- "${files[@]}"
	  fi
	 )
	EOF
      print -n -- '\a'
      if command -v open >/dev/null; then
        open "${folder}"
      fi
    fi

    cleanup
  )

  setopt LOCAL_OPTIONS
}

: '# prerequisites check'
function check() {
  if [ "$(ps -o comm= $$)" = "zsh" -o \
       "$(ps -o comm= $$)" = "-zsh" -o \
       "$(ps -o comm= $$)" = "/bin/zsh" ]; then
    function error_message() { print -- "\033[0;31m$1\033[0m"; }

    local -A programs=(
      'gawk' ''
      'mkdir' ''
      'rm' ''
      'sort' ''
      'tail' ''
      'wget' ''
    )
    for program in "${(@k)programs}"; do
      [[ -n ${program} ]] \
        && { command -v "${program%,*}" >/dev/null \
               || { error_message "${program%,*} is required for the script to work."
                    return 1
                  }
           }
    done

    wget --debug --output-document='/dev/null' https://www.google.com/ 2>&1 \
      | awk '/Debugging support not compiled in/ { exit 1 }' \
      || { error_message "Wget should be compiled with the \"debug\" support."
           return 1
         }
  else
    echo "Zsh is required for the script to work."
    return 1
  fi >&2
}

check \
  && LC_ALL='C' main
```

#### Resulting files:
- `${project}-wget-links.txt` - list of all links found.
- `${project}-wget-links-abs-and-refs.tsv` - list of absolute links found.
- `${project}-wget-links-and-refs.tsv` - to be used at step 2.
- `${project}-wget-sitemap.txt` - list of html links found.
- `${project}-wget.log` - Wget log for debugging purposes.





## Step 2
Specify the same project name as above, and run:

```Shell
 : '# Check links using curl, v2.3.3'

function main() {

  : '# specify the project name*'
  local          project=''

  : '# specify additional HTTP codes (vbar-separated) to exclude from the broken link report'
  local        skip_code=''

  : '# specify a regexp (POSIX ERE) for a custom search (e.g.: check for soft 404s using terms, pages containing forms, etc.), case-insensitive'
  local   custom_query_1=''
  local   custom_query_2=''
  local   custom_query_3=''
  local   custom_query_4=''
  local   custom_query_5=''

  : '# specify curl options (except those after the ${curl_cmd_opts[@]} lines below)'
  local -a curl_cmd_opts=(
      curl
        --disable
        --verbose
        --no-progress-meter
        --stderr
        -
        --write-out
        '\nout_errormsg: %{errormsg}\nout_num_redirects: %{num_redirects}\nout_response_code: %{response_code}\nout_size_header: %{size_header}\nout_size_download: %{size_download}\nout_time_total: %{time_total}\nout_url: %{url}\n\n'
        --location
        --referer
        ';auto'
    )

  : '# specify path for the resulting files'
  local           folder="${HOME}/${project}"


  test -z "${${project:?Specify the project name}:/*/}"

  setopt   LOCAL_TRAPS \
           WARN_CREATE_GLOBAL
  unsetopt UNSET

  SECONDS=0

  local file_broken_links="${folder}/${project}-broken-links-$(print -P '%D{%F-%H%M}').tsv"
  local file_curl_log="${folder}/${project}-curl.log"
  local file_curl_summary="${folder}/${project}-curl-summary.tsv"
  local file_curl_tmp="${${TMPDIR-"${HOME}/tmp"}%/}/curl_tmp_${RANDOM}"
  local -a file_wget_links=( ${(f)"$(< "${folder}/${project}-wget-links.txt")"} )
  local file_wget_links_refs="${folder}/${project}-wget-links-and-refs.tsv"
  local file_wget_log="${folder}/${project}-wget.log"
  local -a file_wget_sitemap=( ${(Lf)"$(< "${folder}/${project}-wget-sitemap.txt")"} )

  local -a wget_log_clip
  function _get_log_clip() {
    local REPLY
    while IFS= read -r; do
      if ! [[ ${REPLY} = 'Queue count'* ]]; then
        wget_log_clip+=( "${REPLY}" )
      else
        break
      fi
    done
  }
  if [[ -a ${file_wget_log} ]]; then
    _get_log_clip < "${file_wget_log}"
  elif [[ -a ${file_wget_log}.zst ]]; then
    if command -v zstdcat >/dev/null; then
      zstdcat --quiet -- "${file_wget_log}.zst" \
        | _get_log_clip
    fi
  fi

  if [[ -a ${file_curl_log} || \
        -a ${file_curl_summary} ]]; then
    local REPLY
    if read -q '?Overwrite existing files? (y/n)'; then
      rm -- "${folder}/${project}-curl"*
      print -l
    else
      return 1
    fi
  fi

  function cleanup() {
    local REPLY
    if [[ -s ${file_curl_summary} ]]; then
      { IFS= read -r
        print -r -- "${REPLY}"
        sort -t $'\t' -k 2.2,2.9dr -s
      } < "${file_curl_summary}" > "${file_curl_summary}.tmp" \
          && mv -- "${file_curl_summary}"{.tmp,}
    else
      rm -- "${file_curl_summary}"
    fi

    rm -f -- "${file_curl_tmp}"

    if command -v zstd >/dev/null; then
      if ! read -t 15 -q $'?\nKeep the log file uncompressed? (y/N)'; then
        zstd --quiet --rm --force -- "${file_curl_log}"
      fi
    fi
  }

  trap cleanup INT TERM QUIT

  ( if [[ ${#wget_log_clip[@]} > 0 ]]; then
      local -i line_index

      : '# retrieve the domain(s) to define the in-scope URLs'
      local -l in_scope
      if (( line_index=${wget_log_clip[(I)Setting --domains*]} )); then
        in_scope="https?://(${${wget_log_clip[${line_index}]:31}//,/|})"
      elif (( line_index=${wget_log_clip[(I)Enqueuing*]} )); then
        in_scope="https?://${${${wget_log_clip[${line_index}]:10:-11}#*//}%%/*}"
      fi

      : '# retrieve the credentials, unless these are specified explicitly in $curl_cmd_opts above'
      if [[ ${curl_cmd_opts[(ie)--user]} -ge ${#curl_cmd_opts[@]} ]]; then
        local -a auth
        if (( line_index=${wget_log_clip[(I)Setting --http-user*]} )); then
          auth=( "${wget_log_clip[${line_index}]:34}" )
          if (( line_index=${wget_log_clip[(I)Setting --http-password*]} )); then
            auth+=( "${wget_log_clip[${line_index}]:42}" )
            curl_cmd_opts+=(
              --user
              "${(j[:])auth[@]}"
            )
          fi
        fi
      fi
    fi

    : '# one curl invocation per each URL allows checking unlimited number of URLs while keeping memory footprint small'
    for url in "${file_wget_links[@]}"; do
      if [[ ${url} =~ '^(mailto|tel|callto|.?.?.?market|consultantplus):' ]]; then
        print -r -- "out_url:" "${url}"
      else
        if [[ ${(L)url} =~ ^${in_scope} ]]; then
          if (( ${file_wget_sitemap[(Ie)${(L)url}]} )); then
            "${curl_cmd_opts[@]/out_url:/out_full_download\nout_url:}" \
              "${url}"
          else
            "${curl_cmd_opts[@]}" \
              --head \
              "${url}"
          fi
        elif [[ ${url} =~ '^https?://((.*)+\.)?vk\.(ru|com)' ]]; then
          : '# brew coffee with a HEAD-less teapot'
          "${curl_cmd_opts[@]}" \
            --fail \
            --output '/dev/null' \
            --user foo:bar \
            "${url}"
        else
          "${curl_cmd_opts[@]}" \
            --head \
            --user foo:bar \
            "${url}"
        fi
      fi
    done > "${file_curl_log}" \
      | gawk -v RS='\r?\n' \
             -v OFS='\t' \
             -v IGNORECASE=1 \
             -v custom_query_1="@/${custom_query_1:-"CUSTOM QUERY"}/" \
             -v custom_query_2="@/${custom_query_2:-"CUSTOM QUERY"}/" \
             -v custom_query_3="@/${custom_query_3:-"CUSTOM QUERY"}/" \
             -v custom_query_4="@/${custom_query_4:-"CUSTOM QUERY"}/" \
             -v custom_query_5="@/${custom_query_5:-"CUSTOM QUERY"}/" \
             -v file_curl_summary="${file_curl_summary}" \
             -v file_curl_tmp="${file_curl_tmp}" \
             -v links_total="${#file_wget_links[@]}" \
             -v no_parser_mx="$(command -v host >/dev/null)$?" \
             -v no_parser_xml="$(command -v xmllint >/dev/null)$?" '
          BEGIN                                  { print "URL",
                                                         "CODE (LAST HOP IF REDIRECT)\342\206\223",
                                                         "TYPE",
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
          /^Warning: Problem.*HTTP error/        { n=1         }
          /<TITLE[^>]*>/, /<\/TITLE>/            { mult_title++
                                                   if (mult_title > 1 && ! n)
                                                     title="MULTIPLE TITLE"
                                                   else
                                                     { if (! no_parser_xml)
                                                         { gsub(/\047/, "\\047")
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
                                                         { gsub(/\047/, "\\047")
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
                                                         { gsub(/\047/, "\\047")
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
                                                         { gsub(/\047/, "\\047")
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
          /^out_full_download/                   { if (! title) title="NO TITLE"                          }
          /^out_url:/                            { f=1

                                                   url=$2

                                                   checked+=1
                                                   if (! time_total) time_total=" --"
                                                     printf "%6d%s%-6d\t%s\t%s\n", checked, "/", links_total, time_total, url

                                                   if (url ~ /^mailto:/)
                                                     { if (url ~ /^mailto:(%20)*[[:alnum:].!#$%&\047*+/=?^_`{|}~-]+@[[:alnum:].-]+\.[[:alpha:]]{2,64}(%20)*(\?.*)?$/)
                                                         { if (! no_parser_mx)
                                                             { cmd="zsh -c '\''host -t MX $({ IFS= read; \
                                                                                              print -- \"${${${REPLY#*@}%%\\?*}//(%20)/}\"; \
                                                                                            } <<<" url")'\''"
                                                               cmd | getline mx_check
                                                               close(cmd)
                                                               if (mx_check ~ /mail is handled by .{4,}/)
                                                                 code="MX found"
                                                               else
                                                                 code=mx_check
                                                             }
                                                           else
                                                             code="No host utility installed"
                                                         }
                                                       else
                                                         code="Bad email syntax"
                                                     }
                                                   else if (url ~ /^(tel|callto):/)
                                                     code="Check manually tel validity"
                                                  else if (url ~ /^(.?.?.?market|consultantplus):/)
                                                     code="Custom URL scheme"
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
      \
      && gawk -v FS='\t' \
              -v OFS='\t' \
              -v file_broken_links="${file_broken_links}" \
              -v skip_code="@/^(MX found|Custom URL scheme|200${skip_code:+"|${skip_code}"})/" '
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
           $1 in seen           { print $1, $2 > file_broken_links }' "${file_curl_summary}" "${file_wget_links_refs}" \
      \
      && <<-EOF

		FINISHED --$(print -P '%D{%F %T}')--
		Total wall clock time: $(
		  local -i t="${SECONDS}"
                  local -i d=$(( t/60/60/24 ))
                  local -i h=$(( t/60/60%24 ))
                  local -i m=$(( t/60%60 ))
                  local -i s=$(( t%60 ))
                  if [[ ${d} > 0 ]]; then
                    printf '%dd ' "${d}"
                  fi
                  if [[ ${h} > 0 ]]; then
                    printf '%dh ' "${h}"
                  fi
                  if [[ ${m} > 0 ]]; then
                    printf '%dm ' "${m}"
                  fi
                  if [[ ${s} > 0 ]]; then
                    printf '%ds' "${s}"
                  fi
		)
		Downloaded: $(< "${file_curl_tmp}")

		CREATED FILES
		$(local -a files=(
		    "${file_broken_links}"
		    "${file_curl_summary}"
		    "${file_curl_log}"
		  )
		  if command -v du >/dev/null; then
		    du -h -- "${files[@]}" 2>/dev/null
		  else
		    print -l -- "${files[@]}"
		  fi
		)
	EOF
    print -n -- '\a'
    sleep 0.3
    print -n -- '\a'
    if command -v open >/dev/null; then
      open "${folder}"
    fi

    cleanup
  )

  setopt LOCAL_OPTIONS
}

: '# prerequisites check'
function check() {
  if [ "$(ps -o comm= $$)" = "zsh" -o \
       "$(ps -o comm= $$)" = "-zsh" -o \
       "$(ps -o comm= $$)" = "/bin/zsh" ]; then
    function error_message() { print -- "\033[0;31m$1\033[0m"; }

    local -A programs=(
      'curl,7.75.0' 'NR == 1 { print $2 }'
      'gawk' ''
      'mv' ''
      'rm' ''
      'sort' ''
    )
    for program awk_code in "${(@kv)programs}"; do
      [[ -n ${program} ]] \
        && { command -v "${program%,*}" >/dev/null \
               || { error_message "${program%,*} is required for the script to work."
                    return 1
                  }
           }
      [[ -n ${awk_code} ]] \
        && { function { [[ $1 = ${${(On)@}[1]} ]]; } $("${program%,*}" --version | awk "${awk_code}") "${program#*,}" \
               || { error_message "The oldest supported version of ${program%,*} is ${program#*,}."
                    return 1
                  }
           }
    done
    true
  else
    echo "Zsh is required for the script to work."
    return 1
  fi >&2
}

check \
  && LC_ALL='C' main
```

#### Resulting files:
- `${project}-broken-links-DD-MM-YYYY-HHSS.tsv` - list of links with HTTP error codes and referring URLs (see the image above).
- `${project}-curl-summary.tsv` - list of all links with other information.
- `${project}-curl.log` - curl log for debugging purposes.

## Caveats
|Caveat|Note|
|-:|:-|
|`BASE`|If a web page contains the BASE tag, the referers in the `${project}-wget-links-abs-and-refs.tsv` file will be incorrect.|
|`--execute robots='off'`|Use the `--reject-regex` Wget option to exclude URLs, not this one.|
|Redirect|The URLs excluded via the `--reject-regex` Wget option will still appear in the link list if they are a redirect target.

## Version history
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
