# Shell link checker
Website broken link checking shell script based on **Wget** and **curl**. The script consists of two one-liners (sort of) to be edited _ad hoc_, copied and pasted into the terminal, and run consecutively.

Most probably, one will need to fine-tune Wget and curl (such as set timeouts, handle HTTP or SSL errors, etc.) with options (consult the respective MAN pages) to get an adapted behavior.

## Features
- Broken link checking
- Email checking
- Website/webpage data collection (TITLE/og:title/og:description extraction, absolute, mailto: and tel: links, etc.)
- Custom term search (useful for checking for soft 404s, etc.)

## Prerequisites
- zsh
- wget compiled with the "debug" feature and PCRE/PCRE2 support
- curl (preferably 7.67.0 or newer)
- GNU grep (with PCRE/PCRE2 support, the same as with wget)
- GNU awk
- GNU coreutils
- xmllint
- host
- lsof
- pkill
- zstd (optional)

![Screenshot](/broken-links.jpg)

## Step 1
Replace `PROJECT_NAME` with the actual project name and `ADDRESS` with the URL to check, and run:

```Shell
 : '# Gather links using Wget, v1.11.1'

function main() {

  setopt   LOCAL_TRAPS \
           WARN_CREATE_GLOBAL
  unsetopt NOMATCH \
           UNSET

  : '# specify the project name*'
  local          project="PROJECT_NAME"

  : '# specify the URL to check*'
  local         address="ADDRESS"

  : '# specify username and password (in the user:password format)'
  local            auth=""

  : '# specify non-empty value if only HTTPS links should be followed'
  local      https_only=""

  : '# specify non-empty value if no-cache headers should be sent'
  local        no_cache=""

  : '# specify user-agent'
  local      user_agent=""

  : '# specify non-empty value to exclude external links from the results. Mutually exclusive with $subtree_only'
  local   internal_only=""

  : '# specify non-empty value to exclude any links up the $address tree (signified with a trailing slash) from the results. Mutually exclusive with $internal_only, but takes precedence'
  local    subtree_only=""

  : '# specify which domains to include (vbar-separated)'
  local -l incl_domains=""

  : '# specify which domains to exclude (vbar-separated)'
  local -l excl_domains=""

  : '# specify a regexp (PCRE/PCRE2) to exclude paths or files'
  local    reject_regex=""

  : '# specify links to exclude from the absolute links check (vbar-separated)'
  local  excl_abs_links=""

  : '# specify path for the resulting files'
  local          folder="${HOME}/${project}"

  if [[ ! -d ${folder} ]]; then
    mkdir "${folder}"
  fi
  local file_wget_links="${folder}/${project}-wget-links.txt"
  local file_wget_links_abs_refs="${folder}/${project}-wget-links-abs-and-refs.tsv"
  local file_wget_links_refs="${folder}/${project}-wget-links-and-refs.tsv"
  local file_wget_log="${folder}/${project}-wget.log"
  local file_wget_sitemap="${folder}/${project}-wget-sitemap.txt"
  local pipe_wget_tmp="$(mktemp --dry-run --tmpdir="${TMPDIR:-"$HOME/tmp"}" 'wget_failed_XXXX')"

  local address_domain="$(cut --delimiter='/' --fields=3 <<< "${address}")"
  local in_scope="https?://(${address_domain}${incl_domains:+"|${incl_domains}"})"

  function if_reject() {
    if [[ -n ${reject_regex} ]]; then
      grep --invert-match --perl-regexp --regexp="${reject_regex}" 2> /dev/null
    else
      >&1
    fi
  }

  function cleanup() {
    pkill -P $$ -x tail
    sleep 0.5
    rm --force -- "${file_wget_links}"(L-1) \
      "${file_wget_links_abs_refs}"(L-1) \
      "${file_wget_links_refs}"(L-1) \
      "${file_wget_sitemap}"(L-1) \
      "${pipe_wget_tmp}"
    print -l
    unsetopt WARN_CREATE_GLOBAL
    if read -s -t 10 -q '?Compress the log file? ([n]/y)'; then
      zstd --rm --force --quiet -- "${file_wget_log}"
    fi
    setopt WARN_CREATE_GLOBAL
  }

  trap cleanup INT TERM QUIT

  : '# show in the terminal only unique "in-scope" URLs'
  tail --lines=0 --sleep-interval=0.1 --follow='name' --retry -- "${file_wget_log}" \
    | gawk --assign in_scope="^${in_scope}" '
        BEGIN             { checked=0          }
        /^Dequeuing/      { getline; queued=$3 }
        /^--[0-9 -:]{19}--/ \
          && $NF ~ 'in_scope' \
          && !seen[$NF]++ { checked+=1
                            percent=sprintf("%.4f", 100-(100*queued/(checked+queued+0.01)))
                            printf "%6d\t%3d%\t\t%s\n", checked, percent, $NF
                          }' &

  ( { wget \
        --debug \
        \
        --directory-prefix="${TMPDIR:-"$HOME/tmp"}" \
        --no-directories \
        \
        ${user_agent:+"--user-agent=${user_agent}"} \
        ${no_cache:+"--no-cache"} \
        \
        --local-encoding='UTF-8' \
        --spider \
        --recursive \
        --level='inf' \
        --page-requisites \
        --no-parent \
        \
        ${auth:+"--http-user=${auth%%:*}"} \
        ${auth:+"--http-password=${auth#*:}"} \
        \
        ${https_only:+"--https-only"} \
        \
        ${incl_domains:+"--span-hosts"} \
        ${incl_domains:+"--domains=${address_domain},${incl_domains//\|/,}"} \
        \
        ${excl_domains:+"--exclude-domains=${excl_domains//\|/,}"} \
        \
        ${reject_regex:+"--regex-type=pcre"} \
        ${reject_regex:+"--reject-regex=${reject_regex}"} \
        \
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
             if tac -- "${file_wget_log}" \
                  | grep --quiet --no-messages --max-count=1 --basic-regexp --regexp='^FINISHED'; then
               printf "\n%s\n" "--WGET SOFT-FAILED WITH ${error_name}${error_code:+" (code ${error_code})"}--" > /dev/tty
             else
               mkfifo "${pipe_wget_tmp}"
               { printf "\e[3m"
                 tail --lines=40 -- "${file_wget_log}"
                 printf "\e[0m"
                 printf "\n%s\n\n%s\n\n" "--WGET FAILED WITH ${error_name} (code ${error_code})--" 'Some last log entries are shown above'
               } > /dev/tty
             fi
           }
           \
    } > "${file_wget_log}" \
      > >(gawk --assign RS='\r?\n' --assign IGNORECASE=1 --assign in_scope="^${in_scope}" '
            /^--[0-9 -:]{19}--/ \
              && $NF ~ 'in_scope'            { url=$NF   }
            /^HTTP\/(0\.9|1\.0|1\.1|2|3)/    { code=$2   }
            /^Content-Type: (text\/html|application\/xhtml\+xml)/ \
              && code ~ /^(200|204|206|304)/ { print url }' \
            | if_reject \
            | sort --unique > "${file_wget_sitemap}"
         ) \
      > >(gawk --assign FPAT="\047[^\047]+\047" --assign OFS='\t' --assign IGNORECASE=1 '
            /\.tmp: merge\(/ { if ($2 !~ /^\047(mailto|tel|javascript|data|unsafe):/)
                                 { gsub(/\047/, "", $1)
                                   split($1, a_parent, "/")
                                   sub(/\/\/www\./, "//", a_parent[3])

                                   gsub(/\047/, "", $2)
                                   split($2, a_absolute, "/")
                                   sub(/\/\/www\./, "//", a_absolute[3])

                                   if (a_parent[3] && a_absolute[3])
                                     if (a_parent[3] == a_absolute[3]) print $2, $1
                                 }
                             }' \
            | if [[ -n ${excl_abs_links} ]]; then
                grep --invert-match --ignore-case --extended-regexp --regexp="${excl_abs_links}$"
              else
                >&1
              fi \
            | sort --unique > "${file_wget_links_abs_refs}"
         ) \
      | gawk --assign OFS='\t' --assign IGNORECASE=1 --assign address="${address}" '
            BEGIN                { print address, "" }
            /^--[0-9 -:]{19}--/  { referer=$NF       }
            /^appending/         { sub(/^appending (\047|\342\200\230)/, "")
                                   sub(/(\047|\342\200\231) to urlpos\.$/, "")
                                   gsub(/\040/, "%20")
                                   print $0, referer
                                 }
            /\.tmp: merged link/ { sub(/.*\.tmp: merged link \042/, "")
                                   sub(/\042 doesn\047t parse\.$/, "")
                                   gsub(/\040/, "%20")
                                   if (/^mailto:/)
                                     print $0, referer
                                   else if (/^tel:/)
                                     print $0, referer
                                   else if (/^(javascript|data):/)
                                     { }
                                   else
                                     print $0, referer
                                 }' \
      | if [[ -n ${subtree_only} ]]; then
          grep --ignore-case --basic-regexp --regexp="^${address}"
        elif [[ -n ${internal_only} ]]; then
          grep --ignore-case --extended-regexp --regexp="^(${in_scope}|(mailto|tel):)"
        else
          >&1
        fi \
      | sort --unique > "${file_wget_links_refs}" \
      | cut --fields=1 \
      | if_reject \
      | sort --unique > "${file_wget_links}"

    : 'if Wget did not hard-fail, show the stats'
    if [[ ! -p ${pipe_wget_tmp} ]]; then
      cat <<-EOF
	
	$(tail --lines=4 -- "${file_wget_log}" \
	    | gawk '
	        /^FINISHED/, 0 { if (/^Downloaded:/)
	                           { print $1, $4; next }
	                           { print $0           }
	                       }'
	 )
	Total links found: $(wc --lines < "${file_wget_links}")

	CREATED FILES
	$(du --human-readable -- "${file_wget_links}" \
	    "${file_wget_links_abs_refs}"(L+1) \
	    "${file_wget_links_refs}" \
	    "${file_wget_sitemap}" \
	    "${file_wget_log}" 2> /dev/null
	 )

	EOF
      printf '\a'
      (( $+commands[open] )) && open "${folder}"
    fi

    cleanup
  )

  setopt LOCAL_OPTIONS
}

LC_ALL='C' main
```

#### Resulting files:
- _PROJECT-NAME-wget-links.txt_ - list of all links found.
- _PROJECT-NAME-wget-links-abs-and-refs.tsv_ - list of absolute links found.
- _PROJECT-NAME-wget-links-and-refs.tsv_ - to be used at step 2.
- _PROJECT-NAME-wget-sitemap.txt_ - list of the html links found.
- _PROJECT-NAME-wget.log_ - Wget log for debugging purposes.





## Step 2
Replace `PROJECT_NAME` with the same project name as above, and run:

```Shell
 : '# Check links using curl, v1.11.1'

function main() {

  setopt   LOCAL_TRAPS \
           WARN_CREATE_GLOBAL
  unsetopt UNSET

  SECONDS=0

  : '# specify the project name*'
  local       project="PROJECT_NAME"

  : '# specify username and password (in the user:password format)'
  local          auth=""

  : '# specify user-agent'
  local    user_agent=""

  : '# specify additional HTTP codes (vbar-separated) to exclude from the broken link report'
  local     skip_code=""

  : '# specify a regexp (POSIX ERE) for a custom search (e.g.: check for soft 404s using terms, pages containing a form, etc.)'
  local custom_search=""

  : '# specify path for the resulting files'
  local        folder="${HOME}/${project}"

  local file_broken_links="${folder}/${project}-broken-links-$(date +"%Y-%m-%d").tsv"
  local file_curl_links="${folder}/${project}-curl-links.tsv"
  local file_curl_log="${folder}/${project}-curl.log"
  local file_wget_links="${folder}/${project}-wget-links.txt"
  local file_wget_links_refs="${folder}/${project}-wget-links-and-refs.tsv"
  local file_wget_sitemap="${folder}/${project}-wget-sitemap.txt"

  function cleanup() {
    pkill -P $$ -x tail
    sleep 0.5
    if [[ $(wc --lines < "${file_curl_links}") -le 1 ]]; then
      rm -- "${file_curl_links}"
    fi
  }

  trap cleanup INT TERM QUIT

  : '# show in the terminal the URLs being checked'
  tail --lines=0 --sleep-interval=0.1 --follow='name' --retry -- "${file_curl_log}" \
    | gawk --assign total="$(wc --lines < "${file_wget_links}")" '
        BEGIN          { checked=0 }
        /^START URL:/  { time_total=""
                         split($0, a_url, "START URL: ")
                       }
        /^time_total:/ { time_total=sprintf("%.2fs", $2) }
        /^END URL:/    { checked+=1
                         if (! time_total) time_total=" --"
                         printf "%6d%s%-6d\t%s\t%s\n", checked, "/", total, time_total, a_url[2]
                       }' &

  ( local -a curl_opts
    curl_opts=(
      --disable
      --include
      --no-progress-meter
      --write-out
      '\nnum_redirects: %{num_redirects}\ntime_total: %{time_total}\nsize_header: %{size_header}\nsize_download: %{size_download}\n'
      ${auth:+"--user"}
      ${auth:+"${auth}"}
      ${user_agent:+"--user-agent"}
      ${user_agent:+"${user_agent}"}
      --location
      --referer
      ';auto'
    )

    while IFS=$'\n' read -r line || [[ -n ${line} ]]; do
      printf "%s\n" "START URL: ${line}"
        if grep --quiet --line-regexp --regexp="${line}" -- "${file_wget_sitemap}" 2> /dev/null; then
          curl \
            "${curl_opts[@]}" \
            --compressed \
            "${line}" 2>&1
        elif grep --quiet --ignore-case --extended-regexp --regexp="^(mailto|tel):" <<< "${line}"; then
          true
        elif grep --quiet --ignore-case --extended-regexp --regexp="^https?://(www\.)?vk\.(ru|com)" <<< "${line}"; then
          : '# brew coffee with a head-less teapot'
          curl \
            "${curl_opts[@]}" \
            --compressed \
            --dump-header - \
            --output /dev/null \
            "${line}" 2>&1
        else
          curl \
            "${curl_opts[@]}" \
            --head \
            "${line}" 2>&1
        fi
        printf "%s\n\n" "END URL: ${line}"
    done < "${file_wget_links}" > "${file_curl_log}" \
      | gawk --assign RS='\r?\n' --assign OFS='\t' --assign IGNORECASE=1 --assign custom_query="${custom_search:-"CUSTOM SEARCH"}" '
          BEGIN                           { print "URL",
                                            "CODE (LAST HOP IF REDIRECT)",
                                            "TYPE",
                                            "SIZE, KB",
                                            "REDIRECT",
                                            "NUM REDIRECTS",
                                            "TITLE",
                                            "og:title",
                                            "og:description",
                                            custom_query
                                          }
          /^START URL:/                   { split($0, a_url, "START URL: ")
                                            url=a_url[2]
                                            code=""
                                            custom_result=""
                                            http_retry=""
                                            multiple_og_desc=""
                                            multiple_og_title=""
                                            multiple_title=""
                                            num_redirects=""
                                            og_desc=""
                                            og_title=""
                                            redirect=""
                                            size=""
                                            title=""
                                            type=""
                                          }
                                          { if (url ~ /^mailto:/) {
                                              if (url ~ /^mailto:(%20)*[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,64}(%20)*(\?.*)?$/)
                                                { cmd="host -t MX $({ cut --delimiter='\''@'\'' --fields=2 \
                                                                        | cut --delimiter='\''?'\'' --fields=1 \
                                                                        | sed '\''s/%20//g'\''; \
                                                                    } <<<" url" \
                                                                   ) | tr '\''\n'\'' '\'' '\''"
                                                  cmd | getline mx_check
                                                  close(cmd)
                                                  if (mx_check ~ /mail is handled by .{4,}/)
                                                    code="200 (MX found)"
                                                  else
                                                    code="host: " mx_check
                                                }
                                              else
                                                code="Bad email syntax"
                                              }
                                            else if (url ~ /^tel:/)
                                              code="Check manually tel validity"
                                            else if (/^HTTP\/(0\.9|1\.0|1\.1|2|3)/)
                                              code=$2
                                            else if (/^curl: \([0-9]{1,2}\)/)
                                              code=$0
                                          }
          /^Content-Length:/              { size=sprintf("%.f", $2/1024)
                                            if (size == 0) size=1
                                          }
          /^Content-Type:/                { split($0, a_ctype, /[:;=]/)
                                            type=a_ctype[2]
                                            gsub(/^\040+|\040+$/, "", type)

                                            charset=a_ctype[4]
                                            gsub(/^\040+|\040+$/, "", charset)
                                            if (! charset) charset="UTF-8"
                                          }
          /^Location:/                    { redirect=$2                   }
          /^num_redirects:/               { if ($2 != 0) num_redirects=$2 }
          /^Warning: Problem.*HTTP error/ { http_retry=1                  }
          /<TITLE[^>]*>/, /<\/TITLE>/     { multiple_title++
                                            if (multiple_title > 1 && ! http_retry)
                                              title="MULTIPLE TITLE"
                                            else
                                              { gsub(/\047/, "\\047")
                                                sub(/<TITLE/, "<meta http-equiv='\''Content-Type'\'' content='\''charset=" charset "'\'' />&")
                                                cmd="{ xmllint \
                                                         --html \
                                                         --xpath '\''//title'\'' \
                                                         - 2> /dev/null \
                                                         | gawk --assign RS='\''</?TITLE[^>]*>'\'' --assign IGNORECASE=1 \
                                                             '\''!(NR%2)'\''; \
                                                     } <<< '\''"$0"'\''"; \
                                                cmd | getline title
                                                close(cmd)

                                                gsub(/^[[:blank:]]+|[[:blank:]]+$/, "", title)
                                                if (! title) title="EMPTY TITLE"
                                              }
                                          }
          /<META.*og:title/, />/          { multiple_og_title++
                                            if (multiple_og_title > 1)
                                              og_title="MULTIPLE OG:TITLE"
                                            else
                                              { gsub(/\047/, "\\047")
                                                sub(/<META/, "<meta http-equiv='\''Content-Type'\'' content='\''charset=" charset "'\'' />&")
                                                cmd="xmllint \
                                                       --html \
                                                       --xpath '\''string(//meta[@property=\"og:title\"]/@content)'\'' \
                                                       - 2> /dev/null \
                                                  <<< '\''"$0"'\''"; \
                                                cmd | getline og_title
                                                close(cmd)
                                              }
                                          }
          /<META.*og:description/, />/    { multiple_og_desc++
                                            if (multiple_og_desc > 1)
                                              og_desc="MULTIPLE OG:DESCRIPTION"
                                            else
                                              { gsub(/\047/, "\\047")
                                                sub(/<META/, "<meta http-equiv='\''Content-Type'\'' content='\''charset=" charset "'\'' />&")
                                                cmd="xmllint \
                                                       --html \
                                                       --xpath '\''string(//meta[@property=\"og:description\"]/@content)'\'' \
                                                       - 2> /dev/null \
                                                  <<< '\''"$0"'\''"; \
                                                cmd | getline og_desc
                                                close(cmd)
                                              }
                                          }
          custom_query != "CUSTOM SEARCH" { if ($0 ~ 'custom_query') custom_result="\342\234\223" }
          /^END URL:/                     { print url,
                                            code,
                                            type,
                                            size,
                                            redirect,
                                            num_redirects,
                                            title,
                                            og_title,
                                            og_desc,
                                            custom_result
                                          }' \
      | { read -r; printf "%s\n" "${REPLY}"
          sort --field-separator=$'\t' --key=2.2,2.9dr --stable
        } > "${file_curl_links}" \
      \
      && : '# make sure the file has finished being written' \
      && while true; do
           if ! lsof -f -- "${file_curl_links}" > /dev/null 2>&1; then
             break
           fi
           sleep 0.5
         done \
      \
      && : '# now to the broken link report generation' \
      && local curl_links_error="$(gawk --assign FS='\t' --assign OFS='\t' --assign skip="^(200${skip_code:+"|${skip_code}"})" '
           $2 !~ 'skip' { print $1, $2 }' "${file_curl_links}")" \
      && if [[ $(wc --lines <<< "${curl_links_error}") -gt 1 ]]; then
           gawk --assign FS='\t' --assign=OFS='\t' '
             BEGIN      { print "BROKEN LINK", "REFERER" }
             NR == FNR  { seen[$1]++; next               }
             $1 in seen { print $1, $2                   }' \
             <(printf "%s" "${curl_links_error}") "${file_wget_links_refs}" \
                 | cat \
                     <(printf "S U M M A R Y\t\n") \
                     <(printf "%s" "${curl_links_error}") \
                     <(printf "\nD E T A I L S\t\n") \
                     - > "${file_broken_links}"
         fi \
      \
      && cat <<-EOF

		FINISHED --$(date +"%F %T")--
		Total wall clock time: $(
		  if [[ $((SECONDS / 3600)) != 0 ]]; then
		    printf "%s " "$((SECONDS / 3600))h"
		  fi
		  if [[ $(((SECONDS / 60) % 60)) != 0 ]]; then
		    printf "%s " "$(((SECONDS / 60) % 60))m"
		  fi
		  if [[ $((SECONDS % 60)) != 0 ]]; then
		    printf "%s" "$((SECONDS % 60))s"
		  fi
		)
		Downloaded: $(gawk '
                  BEGIN             { downloaded=0                }
                  /^size_header:/   { downloaded+=$2              }
                  /^size_download:/ { if ($2 != 0) downloaded+=$2 }
                  END               { print downloaded            }' "${file_curl_log}" \
                  | numfmt --to='iec' --format="%.f"
		)

		CREATED FILES
		$(du --human-readable -- "${file_curl_links}" "${file_curl_log}")
		$(printf '\033[1m'
		  if [[ -f ${file_broken_links} ]]; then
		    du --human-readable -- "${file_broken_links}"
		  else
		    printf "\nNo broken links found"
		  fi
		  printf '\033[0m'
		 )

	EOF
    printf '\a'
    sleep 0.3
    printf '\a'
    (( $+commands[open] )) && open "${folder}"

    cleanup
  )

  setopt LOCAL_OPTIONS
}

LC_ALL='C' main
```

#### Resulting files:
- _PROJECT-NAME-broken-links-DD-MM-YYYY.tsv_ - list of the links with erroneous HTTP codes and referring URLs (see the picture above).
- _PROJECT-NAME-curl-links.tsv_ - list of all the links with HTTP codes and some other information.
- _PROJECT-NAME-curl.log_ - curl log for debugging purposes.


## Version history
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
