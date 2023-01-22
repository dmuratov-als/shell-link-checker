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
- Wget compiled with the "debug" flag
- curl
- grep
- GNU awk
- GNU coreutils
- pkill
- host
- xmllint
- zstd (optional)

![Screenshot](/broken-links.jpg)

## Step 1
Replace `PROJECT-NAME` with the actual project name and `ADDRESS` with the URL to check, and run:

```Shell
 : '# Gather links using Wget, v1.10.1'

function {

  setopt CLOBBER LOCAL_TRAPS MONITOR MULTIOS WARN_CREATE_GLOBAL
  unsetopt UNSET

  : '# specify the project name'
  local project="PROJECT-NAME"

  : '# specify the URL to check'
  local address="ADDRESS"

  : '# specify non-empty value if only HTTPS links should be followed'
  local https_only=""

  : '# specify non-empty value if no-cache headers should be sent'
  local no_cache=""

  : '# specify user-agent'
  local user_agent=""

  : '# specify non-empty value to exclude external links from the results. Mutually exclusive with $subtree_only'
  local internal_only=""

  : '# specify non-empty value to exclude any links up the $address tree (signified with a trailing slash) from the results. Mutually exclusive with $internal_only, but takes precedence'
  local subtree_only=""

  : '# specify which domains to include (comma-separated)'
  local -l incl_domains=""

  : '# specify which domains to exclude (comma-separated)'
  local -l excl_domains=""

  : '# specify a regexp (POSIX ERE) to exclude paths or files'
  local reject_regex=""

  : '# specify links to exclude from the absolute links check (comma-separated)'
  local excl_absolute_links=""

  : '# specify path for the resulting files'
  local folder="${HOME}/${project}"
  if [[ ! -d ${folder} ]]; then
    mkdir "${folder}"
  fi
  local file_wget_links="${folder}/${project}-wget-links.txt"
  local file_wget_links_absolute="${folder}/${project}-wget-links-absolute.tsv"
  local file_wget_links_refs="${folder}/${project}-wget-links-and-refs.tsv"
  local file_wget_log="${folder}/${project}-wget.log"
  local file_wget_sitemap="${folder}/${project}-wget-sitemap.txt"
  local pipe_wget_tmp="$(mktemp --dry-run --tmpdir="${TMPDIR:-"$HOME/tmp"}" 'wget_failed_XXXX')"

  function if_reject() {
    if [[ -z ${reject_regex} ]]; then
      > "$1"
    else
      grep --invert-match --ignore-case --extended-regexp --regexp="${reject_regex}" 2> /dev/null > "$1"
    fi
  }

  function cleanup() {
    pkill -P $$ -x tail
    sleep 0.5
    if [[ ! -s ${file_wget_links} \
      && ${file_wget_links_refs} \
      && ${file_wget_sitemap} \
    ]]; then
      rm -- "${file_wget_links}" \
        "${file_wget_links_refs}" \
        "${file_wget_sitemap}"
      rm --force -- "${pipe_wget_tmp}"
    fi
    if [[ $(wc --lines -- < "${file_wget_links_absolute}") -eq 1 ]]; then
      rm -- "${file_wget_links_absolute}"
    fi
    print
    unsetopt WARN_CREATE_GLOBAL
    if read -s -t 10 -q '?Compress the log file? ([n]/y)'; then
      zstd --rm --force --quiet -- "${file_wget_log}"
    fi
    setopt WARN_CREATE_GLOBAL
  }

  trap cleanup INT TERM QUIT

  : '# count and show in the terminal only unique "in-scope" URLs'
  tail --lines=0 --sleep-interval=0.1 --follow='name' --retry -- "${file_wget_log}" \
    | awk --assign RS='\n' '
        BEGIN                             { checked=0 }
        /^Queue count/                    { queued=$3
                                            percent=sprintf("%.4f", 100 - (100 * queued / (checked + queued + 0.01)))
                                            sub(/\..*/, "", percent)
                                          }
        /^--[0-9 -:]{19}-- / && !a[$NF]++ { checked+=1
                                            gsub(/&quot;\/?/, "", $NF)
                                            sub(/^https?.*http/, "http", $NF)
                                            printf("%6d\t%3d%\t\t%s\n", checked, percent, $NF)
                                          }' &

  ( { wget \
        --debug \
        --directory-prefix="${TMPDIR:-"$HOME/tmp"}" \
        --no-directories \
        ${user_agent:+"--user-agent=${user_agent}"} \
        ${no_cache:+"--no-cache"} \
        --spider \
        --recursive \
        --level='inf' \
        --page-requisites \
        --no-parent \
        ${https_only:+"--https-only"} \
        ${incl_domains:+"--span-hosts"} \
        ${incl_domains:+"--domains=$(echo "${address}" | cut -d'/' -f3),${incl_domains}"} \
        ${excl_domains:+"--exclude-domains=${excl_domains}"} \
        ${reject_regex:+"--regex-type=posix"} \
        ${reject_regex:+"--reject-regex=${reject_regex}"} \
        "${address}" 2>&1 \
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
             if tail --lines=4 -- "${file_wget_log}" \
                  | grep --quiet --no-messages --basic-regexp --regexp='^FINISHED'; then
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
    } >&1 \
      > "${file_wget_log}" \
      > >(awk --assign RS='\r?\n' --assign IGNORECASE=1 '
            /^--[0-9 -:]{19}-- /                              { url=$NF   }
            /^HTTP\//                                         { code=$2   }
            code ~ /200|204|206|304/ \
              && $1 ~ /^Content-Type:/ \
              && $2 ~ /^(text\/html|application\/xhtml\+xml)/ { print url }' \
            | sort --unique \
            | if_reject "${file_wget_sitemap}"
         ) \
      > >(awk --assign RS='\r?\n' --assign FPAT="\047[^\047]+\047" --assign OFS='\t' '
            BEGIN            { print "PARENT LINK", "ABSOLUTE LINK" }
            /\.tmp: merge\(/ { gsub("\047", "", $1)
                               split($1, a_parent, "/")
                               sub("www.", "", a_parent[3])

                               gsub("\047", "", $2)
                               gsub("&quot;", "", $2)
                               split($2, a_absolute, "/")
                               sub("www.", "", a_absolute[3])

                               if (a_parent[3] == a_absolute[3]) print $1, $2
                             }' \
            | if [[ -n ${excl_absolute_links} ]]; then
                grep --invert-match --ignore-case --extended-regexp --regexp="(${excl_absolute_links//\,/|})$"
              else
                >&1
              fi \
            | sort --unique > "${file_wget_links_absolute}"
         ) \
        | awk --assign RS='\r?\n' --assign OFS='\t' --assign address="${address}" '
            BEGIN                { print address, "" }
            /^--[0-9 -:]{19}-- / { email=""
                                   tel=""
                                   referer=$NF
                                 }
            /^appending/         { gsub(/appending |\047|\342\200\230|\342\200\231| to urlpos\.|&quot;\/?/, "")
                                   sub(/^https?.*http/, "http")
                                   gsub("\040", "%20")
                                   print $0, referer
                                 }
            /\.tmp: merge\(/     { if (match($0, / -> mailto:.*/))
                                     { email=substr($0, RSTART+4, RLENGTH)
                                       gsub("\040", "%20", email)
                                       print email, referer
                                     }
                                   else if (match($0, / -> tel:.*/))
                                     { tel=substr($0, RSTART+4, RLENGTH)
                                       gsub("\040", "%20", tel)
                                       print tel, referer
                                     }
                                 }' \
        | sort --key=1 --field-separator=$'\t' --unique -- > "${file_wget_links_refs}" \
        | cut --fields=1 \
            | sort --unique \
            | if [[ -n ${subtree_only} ]]; then
                grep --ignore-case --fixed-strings --regexp="${address}"
              elif [[ -n ${internal_only} ]]; then
                grep --ignore-case --extended-regexp --regexp="$(echo "${address}" | cut -d'/' -f1-3)|^(mailto|tel):"
              else
                >&1
              fi \
            | if_reject "${file_wget_links}"

    : 'if Wget did not hard-fail, show the stats'
    if [[ ! -p ${pipe_wget_tmp} ]]; then
      cat <<-EOF
	
	$(awk --assign RS='\r?\n' '
	    /^FINISHED/, 0 { if ($0 ~ /^Downloaded:/)
	                       { print $1, $4; next }
	                       { print $0           }
	                   }' "${file_wget_log}"
	 )
	Total links found: $(wc --lines -- < "${file_wget_links}")

	CREATED FILES
	$(du --human-readable -- "${file_wget_links}" \
	    "${file_wget_links_absolute}" \
	    "${file_wget_links_refs}" \
	    "${file_wget_sitemap}" \
	    "${file_wget_log}"
	 )

	EOF
      printf '\a'
      open "${folder}"
    fi

    cleanup
  )

  setopt LOCAL_OPTIONS
}
```

#### Resulting files:
- _PROJECT-NAME-wget-links.txt_ - list of all links found.
- _PROJECT-NAME-wget-links-absolute.tsv_ - list of absolute links found.
- _PROJECT-NAME-wget-links-and-refs.tsv_ - to be used at step 2.
- _PROJECT-NAME-wget-sitemap.txt_ - list of the html links found.
- _PROJECT-NAME-wget.log.zst_ - Wget log for debugging purposes.





## Step 2
Replace `PROJECT-NAME` with the same project name as above, and run:

```Shell
 : '# Check links using curl, v1.10.1'

function {

  setopt CLOBBER LOCAL_TRAPS MONITOR MULTIOS WARN_CREATE_GLOBAL
  unsetopt UNSET

  SECONDS=0

  : '# specify the project name'
  local project="PROJECT-NAME"

  : '# specify user-agent'
  local user_agent=""

  : '# specify additional HTTP codes (comma-separated) to exclude from the broken link report'
  local skip_code=""

  : '# specify a snippet for a custom search (e.g.: check for soft 404s using terms, pages containing a form, etc.)'
  local custom_search=""

  : '# specify path for the resulting files'
  local folder="${HOME}/${project}"
  local file_broken_links="${folder}/${project}-broken-links-$(date +"%Y-%m-%d").tsv"
  local file_curl_links="${folder}/${project}-curl-links.tsv"
  local file_curl_log="${folder}/${project}-curl.log"
  local file_wget_links="${folder}/${project}-wget-links.txt"
  local file_wget_links_refs="${folder}/${project}-wget-links-and-refs.tsv"
  local file_wget_sitemap="${folder}/${project}-wget-sitemap.txt"

  function cleanup() {
    pkill -P $$ -x tail
    sleep 0.5
    if [[ ! -s ${file_curl_links} ]]; then
      rm -- "${file_curl_links}"
    fi
  }

  trap cleanup INT TERM QUIT

  : '# count and show in the terminal the URLs being checked'
  tail --lines=0 --sleep-interval=0.1 --follow='name' --retry -- "${file_curl_log}" \
    | awk --assign RS='\n' --assign total="$(wc --lines -- < "${file_wget_links}")" '
        BEGIN          { checked=0                       }
        /^START URL:/  { time_total=""
                         split($0, a_url, "START URL: ")
                       }
        /^time_total:/ { time_total=sprintf("%.2fs", $2) }
        /^END URL:/    { checked+=1
                         if (! time_total) time_total=" --"
                         printf("%6d%s%-6d\t%s\t%s\n", checked, "/", total, time_total, a_url[2])
                       }' &

  ( local -a curl_opts
    curl_opts=(
      --disable
      --include
      --no-progress-meter
      --write-out
      '\nnum_redirects: %{num_redirects}\ntime_total: %{time_total}\n'
      ${user_agent:+"--user-agent"}
      ${user_agent:+"${user_agent}"}
      --location
      --referer
      ';auto'
    )
    while IFS=$'\n' read -r line; do
      printf "%s\n" "START URL: ${line}"
        if grep --quiet --line-regexp --regexp="${line}" -- "${file_wget_sitemap}" 2> /dev/null; then
          curl \
            "${curl_opts[@]}" \
            --compressed \
            "${line}" 2>&1
        elif grep --quiet --ignore-case --extended-regexp --regexp="^(mailto|tel):" <<< "${line}"; then
          true
        else
          curl \
            "${curl_opts[@]}" \
            --head \
            "${line}" 2>&1
        fi
        printf "%s\n\n" "END URL: ${line}"
    done < "${file_wget_links}" > "${file_curl_log}" \
      | awk --assign RS='\r?\n' --assign OFS='\t' --assign IGNORECASE=1 --assign custom_query="${custom_search:-"CUSTOM SEARCH"}" '
          BEGIN                       { print "URL",
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
          /^START URL:/               { split($0, a_url, "START URL: ")
                                        url=a_url[2]
                                        code=""
                                        custom_result=""
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
                                          if (url ~ /^mailto:(%20)*[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,64}(%20)*(\?.*)?$/)
                                            { cmd="host -t MX $({ cut -d'\''@'\'' -f2 \
                                                                    | cut -d'\''?'\'' -f1 \
                                                                    | sed '\''s/%20//g'\''; \
                                                                } <<<" url") | tr '\''\n'\'' '\'' '\''"
                                              cmd | getline mx_check
                                              close(cmd)
                                              if (mx_check ~ /.* mail is handled by .{4,}/)
                                                code="200 (MX found)"
                                              else
                                                code=mx_check
                                            }
                                          else
                                            code="Bad email syntax"
                                          }
                                        else if (url ~ /^tel:/) {
                                          if (url ~ /^tel:\+?[0-9]+/)
                                            code="200 (OK)"
                                          else
                                            code="Check tel syntax"
                                          }
                                        else if (/^HTTP\//)
                                          code=$2
                                        else if (/^curl: \([0-9]{1,2}\)/)
                                          code=$0
                                      }
          /^Content-Length:/          { size=sprintf("%.f", $2 / 1024); if (size == 0) size=1 }
          /^Content-Type:/            { split($0, a, /[:;=]/)
                                        type=a[2]
                                        charset=a[4]; if (! charset) charset="UTF-8"
                                      }
          /^Location:/                { redirect=$2 }
          /^num_redirects:/           { if ($2 != 0) num_redirects=$2 }
          /<TITLE[^>]*>/, /<\/TITLE>/ { multiple_title++
                                        if (multiple_title > 1)
                                          title="MULTIPLE TITLE"
                                        else
                                          { gsub("\047", "\\047")
                                            sub("<TITLE", "<meta http-equiv='\''Content-Type'\'' content='\''charset=" charset "'\'' />&")
                                            cmd="{ xmllint \
                                                     --encode utf8 \
                                                     --noblanks \
                                                     --html \
                                                     --xpath '\''//title'\'' \
                                                     - 2> /dev/null \
                                                     | awk --assign RS='\''</?TITLE[^>]*>'\'' --assign IGNORECASE=1 \
                                                         '\''!(NR%2)'\''; \
                                                   } <<< '\''"$0"'\''"; \
                                            cmd | getline title
                                            close(cmd)

                                            gsub(/^[ \t]+|[ \t]+$/, "", title)
                                            if (! title) title="EMPTY TITLE"
                                          }
                                      }
          /<META.*og:title/,/>/       { multiple_og_title++
                                        if (multiple_og_title > 1)
                                          og_title="MULTIPLE OG:TITLE"
                                        else
                                          { gsub("\047", "\\047")
                                            sub("<META", "<meta http-equiv='\''Content-Type'\'' content='\''charset=" charset "'\'' />&")
                                            cmd="xmllint \
                                                   --encode utf8 \
                                                   --noblanks \
                                                   --html \
                                                   --xpath '\''string(//meta[@property=\"og:title\"]/@content)'\'' \
                                                   - 2> /dev/null \
                                              <<< '\''"$0"'\''"; \
                                            cmd | getline og_title
                                            close(cmd)
                                          }
                                      }
          /<META.*og:description/,/>/ { multiple_og_desc++
                                        if (multiple_og_desc > 1)
                                          og_desc="MULTIPLE OG:DESCRIPTION"
                                        else
                                          { gsub("\047", "\\047")
                                            sub("<META", "<meta http-equiv='\''Content-Type'\'' content='\''charset=" charset "'\'' />&")
                                            cmd="xmllint \
                                                   --encode utf8 \
                                                   --noblanks \
                                                   --html \
                                                   --xpath '\''string(//meta[@property=\"og:description\"]/@content)'\'' \
                                                   - 2> /dev/null \
                                              <<< '\''"$0"'\''"; \
                                            cmd | getline og_desc
                                            close(cmd)
                                          }
                                      }
          { if (custom_query != "CUSTOM SEARCH") { if ($0 ~ 'custom_query') custom_result="\342\234\223" } }
          /^END URL:/                 { print url,
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
      | { sed --unbuffered 1q
          sort --key=2 --field-separator=$'\t' --reverse
        } > "${file_curl_links}" \
        \
      && : '# infamously make sure the file has finished being written' \
      && sleep 2 \
      \
      && : '# now to the broken link report generation' \
      && local curl_links_error="$(
           { awk --assign RS='\r?\n' --assign FS='\t' --assign OFS='\t' --assign skip="^(200${skip_code:+"|${skip_code//\,/|}"})" '
               $2 !~ 'skip' { print $1, $2 }' \
               | sort --key=1 --field-separator=$'\t'
           } < "${file_curl_links}"
         )" \
      && if [[ $(wc --lines <<< "${curl_links_error}") -gt 1 ]]; then
           awk --assign RS='\r?\n' --assign FS='\t' --assign=OFS='\t' '
             BEGIN     { print "BROKEN LINK", "REFERER" }
             NR == FNR { a[$1]++; next                  }
             $1 in a   { print $1, $2                   }' \
             <(printf "%s" "${curl_links_error}") "${file_wget_links_refs}" \
                 | cat \
                     <(printf "S U M M A R Y\t\n") \
                     <(printf "%s" "${curl_links_error}") \
                     <(printf "\nD E T A I L S\t\n") \
                     - -- > "${file_broken_links}"
         fi \
      \
      && cat <<-EOF

		FINISHED --$(date +"%F %T")--
		Total wall clock time: $(($SECONDS / 3600))h $((($SECONDS / 60) % 60))m $(($SECONDS % 60))s

		CREATED FILES
		$(du --human-readable -- "${file_curl_links}" "${file_curl_log}")
		$(printf "\033[1m"
		  if [[ -f ${file_broken_links} ]]; then
		    du --human-readable -- "${file_broken_links}"
		  else
		    printf "\nNo broken links found"
		  fi
		  printf "\033[0m"
		 )

	EOF
    printf '\a'
    sleep 0.3
    printf '\a'
    open "${folder}"

    cleanup
  )

  setopt LOCAL_OPTIONS
}
```

#### Resulting files:
- _PROJECT-NAME-broken-links-DD-MM-YYYY.tsv_ - list of the links with erroneous HTTP codes and referring URLs (see the picture above).
- _PROJECT-NAME-curl-links.tsv_ - list of all the links with HTTP codes and some other information.
- _PROJECT-NAME-curl.log.zst_ - curl log for debugging purposes.


## Known bugs
Wget does not parse correctly links like `url(&quot;https://web.site/&quot;)` considering it relative like `https://web.site/&quot;https://web.site/&quot;`
and hence will not retrieve the links it could possibly contain. Aside from this, we handle such cases (partially since v1.6.0) and append the correct link to the links list.


## Version history
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
