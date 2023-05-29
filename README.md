# Shell link checker
Website broken link checking shell script based on **Wget** and **curl**. The script consists of two one-liners (sort of) to be edited _ad hoc_, copied and pasted into the terminal, and run consecutively.

Most probably, one will need to fine-tune Wget and curl (such as specify credentials, set timeouts, include / exclude files, paths or domains, mimic a browser, handle HTTP or SSL errors, etc.) with options (consult the respective MAN pages) to get an adapted behavior.

## Features
- Broken link checking, incl. webmanifest/browserconfig parsing
- Email checking
- Data collection (TITLE/META description/og:title/og:description extraction; absolute, mailto and tel links; etc.)
- Custom term search (useful for checking for soft 404s, etc.)

## Prerequisites
- zsh
- wget compiled with the "debug" support
- curl 7.75.0 or newer
- GNU awk
- xmllint
- host
- shell utilities (du, mkdir, mv, rm, sort, tail, wc)
- numfmt
- zstd (optional)

![Screenshot](/broken-links.jpg)

## Step 1
Specify your project name and the URL to check, and run:

```Shell
 : '# Gather links using Wget, v2.1.0'

function main() {

  : '# specify the project name*'
  local         project=''

  : '# specify the URL to check*'
  local         address=''

  : '# specify non-empty value to exclude external links from the results. Mutually exclusive with $subtree_only'
  local   internal_only=''

  : '# specify non-empty value to exclude any links up the $address tree (ending with a trailing slash) from the results. Mutually exclusive with $internal_only, but takes precedence'
  local    subtree_only=''

  : '# specify a regexp (POSIX ERE) to exclude links from the absolute links check'
  local  excl_links_abs=''

  : '# specify Wget options'
  local -a wget_opts=(
      --no-config
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
    mkdir "${folder}"
  fi

  local file_wget_links="${folder}/${project}-wget-links.txt"
  local file_wget_links_abs_refs="${folder}/${project}-wget-links-abs-and-refs.tsv"
  local file_wget_links_refs="${folder}/${project}-wget-links-and-refs.tsv"
  local file_wget_log="${folder}/${project}-wget.log"
  local file_wget_sitemap="${folder}/${project}-wget-sitemap.txt"
  local file_wget_error="${${TMPDIR%/}:-"${HOME}/tmp"}/wget_failed_$[${RANDOM}%1000]"
  local file_wget_tmp="${${TMPDIR%/}:-"${HOME}/tmp"}/wget_tmp_$[${RANDOM}%1000]"

  local opt_index
  if (( opt_index = ${wget_opts[(I)--domains=*]} )); then
    local -l in_scope="https?://(${${wget_opts[${opt_index}]#*=}//,/|})"
  else
    local -l in_scope="https?://${${address#*//}%%/*}"
  fi

  function cleanup() {
    local file
    for file in "${file_wget_links}" \
                "${file_wget_links_abs_refs}" \
                "${file_wget_links_refs}" \
                "${file_wget_sitemap}"; do
      if [[ -s ${file} ]]; then
        sort -u -o "${file}"{,}
      else
        rm -f -- "${file}"
      fi
    done

    rm -f -- "${file_wget_error}" "${file_wget_tmp}"

    local REPLY
    if read -t 15 -q $'?\nCompress the log file? ([n]/y)'; then
      zstd --quiet --rm --force -- "${file_wget_log}"
    fi
  }

  trap cleanup INT TERM QUIT

  ( { wget \
        --debug \
        --no-directories \
        --directory-prefix="${TMPDIR:-"${HOME}/tmp"}" \
        --execute robots='off' \
        --level='inf' \
        --page-requisites \
        --no-parent \
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
               -v internal_only="@/${internal_only:+"^(${in_scope}|(mailto|tel|unsafe):)"}/" \
               -v subtree_only="@/${subtree_only:+"^${address}"}/" \
               -v wget_opts="$(print -r -- ${(q+)wget_opts[*]//\\/\\\\})" '

            function print_to_screen(_link, type) {
              if (type == 1)
                printf "%6d\t%3d%\t\t%s\n", checked, percent, _link
              else if (type == 2)
                printf "%6s\t%3s\t\t%s%s\n", "\040", "\040", "\342\224\224\342\224\200>", _link
            }
        
            function _print_to_file(_link, _referer) {
              print _link, _referer > file_wget_links_refs
              print _link > file_wget_links
            }

            function print_to_file(_link, _referer) {
             if (subtree_only)
                { if (_link ~ subtree_only)
                    _print_to_file(_link, _referer)
                }
              else if (internal_only)
                { if (_link ~ internal_only)
                    _print_to_file(_link, _referer)
                }
              else
                _print_to_file(_link, _referer)
            }
            
            function construct_url(_url) {
              gsub(/\040/, "%20")
              if (/^\//)
                { match(referer, /^https?:\/\/[^\/]*/)
                  url=(substr(referer, RSTART, RLENGTH) $0)
                  print_to_screen(url, 2)
                  print_to_file(url, referer)
                }
              else if (/^https?/)
                { print_to_screen($0, 2)
                  print_to_file($0, referer)
                  if ((! excl_links_abs) || ($0 !~ excl_links_abs))
                    { print $0, referer > file_wget_links_abs_refs }
                }
              else
                { url=(gensub(/[^\/]*$/, "", 1, referer) $0)
                  print_to_screen(url, 2)
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
                                                                       print_to_screen(referer, 1)
                                                                     }

                                                                   if (referer ~ /\.webmanifest|manifest\.json|browserconfig\.xml/)
                                                                     { cmd="wget "\
                                                                              wget_opts "\
                                                                              --quiet \
                                                                              --output-document - "\
                                                                              referer
                                                                       while (cmd | getline)
                                                                         { if (/\042src\042:/)
                                                                             { sub(/[[:blank:]]*\042src\042:[[:blank:]]*/, "")
                                                                               gsub(/\042/, "")
                                                                               sub(/,$/, "")
                                                                               if ($0)
                                                                                 construct_url($0)
                                                                             }
                                                                           else if (/<.*src=\042/)
                                                                             { sub(/.*src=\042/, "")
                                                                               sub(/\042[[:blank:]]*\/>$/, "")
                                                                               if ($0)
                                                                                 construct_url($0)
                                                                             }
                                                                         }
                                                                       close(cmd)
                                                                     }
                                                                 }
            /^---response begin---/, /^---response end---/       { if (referer ~ in_scope)
                                                                     { if (/^HTTP\//)
                                                                         response_code=$2
                                                                       if ((/^Content-Type: (text\/html|application\/xhtml\+xml)/) \
                                                                             && response_code ~ /(200|204|206|304)/)
                                                                         print referer > file_wget_sitemap
                                                                     }
                                                                 }
            /\.tmp: merge\(\047/                                 { split($0, urls, "\047")
                                                                   if (urls[4] !~ /^(mailto|tel|javascript|data|unsafe):/)
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
            /^Deciding whether to enqueue/                       { link=$0
                                                                   getline
                                                                   if (! /is excluded\/not-included through regex\.$/)
                                                                     { sub(/^Deciding whether to enqueue \042/, "", link)
                                                                       sub(/\042\.$/, "", link)
                                                                       gsub(/\040/, "%20", link)
                                                                       print_to_file(link, referer)
                                                                     }
                                                                 }
            /merged link .* doesn\047t parse\.$/                 { sub(/.* merged link \042/, "")
                                                                   sub(/\042 doesn\047t parse\.$/, "")
                                                                   gsub(/\040/, "%20")
                                                                   if (/^(javascript|data):/)
                                                                     { }
                                                                   else
                                                                     print_to_file($0, referer)
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
	Total links found: $(sort -u "${file_wget_links}" \
	                       | wc -l)

	CREATED FILES
	$(du -h -- "${file_wget_links}" \
	           "${file_wget_links_abs_refs}" \
	           "${file_wget_links_refs}" \
	           "${file_wget_sitemap}" \
	           "${file_wget_log}" 2>/dev/null
	 )
	EOF
      print -n -- '\a'
      if (( $+commands[open] )); then
        open "${folder}"
      fi
    fi

    cleanup
  )

  setopt LOCAL_OPTIONS
}

: '# prerequisites check'
function check() {
  if [ "$(ps -o comm= $$)" = "zsh" -o "$(ps -o comm= $$)" = "-zsh" ]; then
    function error_message() { print -- "\033[0;31m$1\033[0m"; }

    local -A programs=(
      'du' ''
      'gawk' ''
      'mkdir' ''
      'rm' ''
      'sort' ''
      'tail' ''
      'wc' ''
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
- _PROJECT-NAME-wget-links.txt_ - list of all links found.
- _PROJECT-NAME-wget-links-abs-and-refs.tsv_ - list of absolute links found.
- _PROJECT-NAME-wget-links-and-refs.tsv_ - to be used at step 2.
- _PROJECT-NAME-wget-sitemap.txt_ - list of the html links found.
- _PROJECT-NAME-wget.log_ - Wget log for debugging purposes.





## Step 2
Specify the same project name as above, and run:

```Shell
 : '# Check links using curl, v2.1.0'

function main() {

  : '# specify the project name*'
  local       project=''

  : '# specify additional HTTP codes (vbar-separated) to exclude from the broken link report'
  local     skip_code=''

  : '# specify a regexp (POSIX ERE) for a custom search (e.g.: check for soft 404s using terms, pages containing forms, etc.), case-insensitive'
  local custom_search=''

  : '# specify curl options'
  local -a curl_cmd_opts=(
      curl
        --disable
        --include
        --no-progress-meter
        --stderr
        -
        --write-out
        '\nwo_errormsg: %{errormsg}\nwo_num_redirects: %{num_redirects}\nwo_response_code: %{response_code}\nwo_size_header: %{size_header}\nwo_size_download: %{size_download}\nwo_time_total: %{time_total}\nwo_url: %{url}\n\n'
        --location
        --referer
        ';auto'
    )

  : '# specify path for the resulting files'
  local        folder="${HOME}/${project}"


  test -z "${${project:?Specify the project name}:/*/}"
  
  setopt   LOCAL_TRAPS \
           WARN_CREATE_GLOBAL
  unsetopt UNSET

  SECONDS=0

  local file_broken_links="${folder}/${project}-broken-links-$(print -P '%D{%Y-%m-%d}').tsv"
  local file_curl_links="${folder}/${project}-curl-links.tsv"
  local file_curl_log="${folder}/${project}-curl.log"
  local file_curl_tmp="${${TMPDIR%/}:-"${HOME}/tmp"}/curl_tmp_$[${RANDOM}%1000]"
  local -a file_wget_links=( ${(f)"$(< "${folder}/${project}-wget-links.txt")"} )
  local file_wget_links_refs="${folder}/${project}-wget-links-and-refs.tsv"
  local -a file_wget_sitemap=( ${(f)"$(< "${folder}/${project}-wget-sitemap.txt")"} )

  function cleanup() {
    local REPLY
    { read -r
      print -r -- "${REPLY}"
      sort -t $'\t' -k 2.2,2.9dr -s
    } < "${file_curl_links}" > "${file_curl_links}.tmp" \
        && mv "${file_curl_links}"{.tmp,}
    
    rm -f -- "${file_curl_tmp}"
  }

  trap cleanup INT TERM QUIT

  ( : '# one curl invocation per each URL allows checking unlimited number of URLs while keeping memory footprint small'
    for url in "${file_wget_links[@]}"; do
      if [[ ${url:l} =~ ^(mailto|tel): ]]; then
        print -r -- "wo_url:" "${url}"
      else
        if (( ${file_wget_sitemap[(Ie)${url}]} )); then
          "${curl_cmd_opts[@]}" \
            --compressed \
            "${url}"
        elif [[ ${url:l} =~ ^https?://((.*)+\.)?vk\.(ru|com) ]]; then
          : '# brew coffee with a head-less teapot'
          "${curl_cmd_opts[@]}" \
            --compressed \
	    --dump-header - \
            --output '/dev/null' \
            "${url}"
        else
          "${curl_cmd_opts[@]}" \
            --head \
            "${url}"
        fi
      fi
    done > "${file_curl_log}" \
      | gawk -v RS='\r?\n' \
             -v OFS='\t' \
             -v IGNORECASE=1 \
             -v custom_query="@/${custom_search:-"CUSTOM SEARCH"}/" \
             -v file_curl_links="${file_curl_links}" \
             -v file_curl_tmp="${file_curl_tmp}" \
             -v links_total="${#file_wget_links[@]}" '
          BEGIN                                  { print "URL",
                                                         "CODE (LAST HOP IF REDIRECT)",
                                                         "TYPE",
                                                         "SIZE, KB",
                                                         "REDIRECT",
                                                         "NUM REDIRECTS",
                                                         "TITLE",
                                                         "og:title",
                                                         "og:description",
                                                         "description",
                                                         custom_query > file_curl_links
                                                 }
          /^Content-Length:/                     { size=sprintf("%.f", $2/1024)
                                                   if (size == 0) size=1
                                                 }
          /^Content-Type:/                       { split($0, a_ctype, /[:;=]/)
                                                   type=a_ctype[2]
                                                   gsub(/^\040+|\040+$/, "", type)

                                                   charset=a_ctype[4]
                                                   gsub(/^\040+|\040+$/, "", charset)
                                                   if (! charset) charset="UTF-8"
                                                 }
          /^Location:/                           { redirect=$2 }
          /^Warning: Problem.*HTTP error/        { n=1         }
          /<TITLE[^>]*>/, /<\/TITLE>/            { multiple_title++
                                                   if (multiple_title > 1 && ! n)
                                                     title="MULTIPLE TITLE"
                                                   else
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
                                                 }
          /<META.*og:title/, />/                 { multiple_og_title++
                                                   if (multiple_og_title > 1)
                                                     og_title="MULTIPLE OG:TITLE"
                                                   else
                                                     { gsub(/\047/, "\\047")
                                                       sub(/<META/, "<meta http-equiv='\''Content-Type'\'' content='\''charset=" charset "'\'' />&")
                                                       cmd="xmllint \
                                                              --html \
                                                              --xpath '\''string(//meta[@property=\"og:title\"]/@content)'\'' \
                                                              - 2>/dev/null <<< '\''"$0"'\''"; \
                                                       cmd | getline og_title
                                                       close(cmd)
                                                     }
                                                 }
          /<META.*og:description/, />/           { multiple_og_desc++
                                                   if (multiple_og_desc > 1)
                                                     og_desc="MULTIPLE OG:DESCRIPTION"
                                                   else
                                                     { gsub(/\047/, "\\047")
                                                       sub(/<META/, "<meta http-equiv='\''Content-Type'\'' content='\''charset=" charset "'\'' />&")
                                                       cmd="xmllint \
                                                              --html \
                                                              --xpath '\''string(//meta[@property=\"og:description\"]/@content)'\'' \
                                                              - 2>/dev/null <<< '\''"$0"'\''"; \
                                                       cmd | getline og_desc
                                                       close(cmd)
                                                     }
                                                 }
          /<META.*name=\042description\042/, />/ { multiple_desc++
                                                   if (multiple_desc > 1)
                                                     desc="MULTIPLE DESCRIPTION"
                                                   else
                                                     { gsub(/\047/, "\\047")
                                                       sub(/<META/, "<meta http-equiv='\''Content-Type'\'' content='\''charset=" charset "'\'' />&")
                                                       cmd="xmllint \
                                                              --html \
                                                              --xpath '\''string(//meta[@name=\"description\"]/@content)'\'' \
                                                              - 2>/dev/null <<< '\''"$0"'\''"; \
                                                       cmd | getline desc
                                                       close(cmd)
                                                     }
                                                 }
          custom_query != "CUSTOM SEARCH"        { if ($0 ~ custom_query) custom_result="\342\234\223" }
          /^wo_errormsg/                         { errormsg=substr($0, 14)                             }
          /^wo_num_redirects:/                   { if ($2 != 0) num_redirects=$2                       }
          /^wo_response_code/                    { response_code=$2                                    }
          /^wo_size_header:/                     { downloaded+=$2                                      }
          /^wo_size_download:/                   { if ($2 != 0) downloaded+=$2                         }
          /^wo_time_total:/                      { time_total=sprintf("%.2fs", $2)                     }
          /^wo_url:/                             { f=1

                                                   url=$2
                                            
                                                   checked+=1
                                                   if (! time_total) time_total=" --"
                                                     printf "%6d%s%-6d\t%s\t%s\n", checked, "/", links_total, time_total, url

                                                   if (url ~ /^mailto:/)
                                                     { if (url ~ /^mailto:(%20)*[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,64}(%20)*(\?.*)?$/)
                                                         { cmd="zsh -c '\''host -t MX $({ read; \
                                                                                          print -- \"${${${REPLY#*@}%%\\?*}//(%20)/}\"; \
                                                                                        } <<<" url")'\''"
                                                           cmd | getline mx_check
                                                           close(cmd)
                                                           if (mx_check ~ /mail is handled by .{4,}/)
                                                             code="200 (MX found)"
                                                           else
                                                             code=mx_check
                                                         }
                                                       else
                                                         code="Bad email syntax"
                                                     }
                                                   else if (url ~ /^tel:/)
                                                     code="Check manually tel validity"
                                                   else if (response_code != 000)
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
                                                         custom_result > file_curl_links
                                                 }
          f                                      { code=""
                                                   custom_result=""
                                                   desc=""
                                                   errormsg=""
                                                   multiple_desc=""
                                                   multiple_og_desc=""
                                                   multiple_og_title=""
                                                   multiple_title=""
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
          END                                    { print downloaded > file_curl_tmp }' \
      \
      && gawk -v FS='\t' \
              -v OFS='\t' \
              -v file_broken_links="${file_broken_links}" \
              -v skip_code="@/^(200${skip_code:+"|${skip_code}"})/" '
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
           $1 in seen           { print $1, $2 > file_broken_links }' "${file_curl_links}" "${file_wget_links_refs}" \
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
		Downloaded: $(numfmt --to='iec' --format="%.f" < "${file_curl_tmp}")

		CREATED FILES
		$(du -h -- "${file_broken_links}" \
		           "${file_curl_links}" \
		           "${file_curl_log}" 2>/dev/null
		)

	EOF
    print -n -- '\a'
    sleep 0.3
    print -n -- '\a'
    if (( $+commands[open] )); then
      open "${folder}"
    fi

    cleanup
  )

  setopt LOCAL_OPTIONS
}

: '# prerequisites check'
function check() {
  if [ "$(ps -o comm= $$)" = "zsh" -o "$(ps -o comm= $$)" = "-zsh" ]; then
    function error_message() { print -- "\033[0;31m$1\033[0m"; }

    local -A programs=(
      'curl,7.75.0' 'NR == 1 { print $2 }'
      'du' ''
      'gawk' ''
      'host' ''
      'mv' ''
      'numfmt' ''
      'rm' ''
      'sort' ''
      'xmllint' ''
    )
    for program awk_code in "${(@kv)programs}"; do
      [[ -n ${program} ]] \
        && { command -v "${program%,*}" >/dev/null \
               || { error_message "${program%,*} is required for the script to work."
                    return 1
                  }
           }
      [[ -n ${awk_code} ]] \
        && { function { [[ $1 == ${${(On)@}[1]} ]]; } $("${program%,*}" --version | awk "${awk_code}") "${program#*,}" \
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
- _PROJECT-NAME-broken-links-DD-MM-YYYY.tsv_ - list of the links with erroneous HTTP codes and referring URLs (see the picture above).
- _PROJECT-NAME-curl-links.tsv_ - list of all the links with some other information.
- _PROJECT-NAME-curl.log_ - curl log for debugging purposes.


## Version history
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
