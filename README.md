# Shell link checker
Website broken link checking shell script based on **Wget** and **curl**. The script consists of two one-liners (sort of) to be edited _ad hoc_, copied and pasted into the terminal, and run consecutively.

Most probably, one will need to fine-tune Wget and curl (such as set timeouts, include / exclude files, paths or domains, mimic a browser, handle HTTP or SSL errors, etc.) with options (consult the respective MAN pages) to get an adapted behavior.

### Prerequisites
- zsh
- Wget compiled with the "debug" flag and libpcre support
- curl
- grep compiled with libpcre support
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
 : '# Gather links using Wget'; \
\
function { \
  \
  setopt LOCAL_TRAPS MONITOR MULTIOS; \
  unsetopt UNSET; \
  \
  : '# specify the project name'; \
  local project='PROJECT-NAME'; \
  \
  : '# specify the URL to check'; \
  local address='ADDRESS'; \
  \
  : '# specify any value to exclude external links from the results. Mutually exclusive with $subtree_only'; \
  local internal_only=''; \
  \
  : '# specify any value to exclude any links up the $address tree from the results. Mutually exclusive with $internal_only'; \
  local subtree_only=''; \
  \
  : '# specify a regexp (PCRE) to exclude paths or files'; \
  local reject_regex=''; \
  \
  : '# specify path for the resulting files'; \
  local folder="${HOME}/${project}"; \
  if [[ ! -d "${folder}" ]]; then \
    mkdir "${folder}"; \
  fi; \
  local file_wget_links="${folder}/${project}-wget-links.txt"; \
  local file_wget_links_refs="${folder}/${project}-wget-links-and-refs.tsv"; \
  local file_wget_sitemap="${folder}/${project}-wget-sitemap.txt"; \
  local file_wget_log="${folder}/${project}-wget.log"; \
  local pipe_wget_tmp=$(mktemp --dry-run --tmpdir="${TMPDIR:-/tmp}" 'wget_failed_XXXX'); \
  \
  function if_reject() { \
    if [[ -z ${reject_regex} ]]; then \
      > $1; \
    else \
      grep --invert-match --ignore-case --perl-regexp --regexp="${reject_regex}" 2> /dev/null \
        > $1; \
    fi \
  }; \
  \
  function cleanup() { \
    pkill -P $$ -x tail; sleep 1; \
    if [[ ! -s ${file_wget_links} && ${file_wget_links_refs} && ${file_wget_sitemap} ]]; then \
      rm --interactive='once' "${file_wget_links}" "${file_wget_links_refs}" "${file_wget_sitemap}"; \
      rm --interactive='once' --force "${pipe_wget_tmp}"; \
    fi; \
    echo; \
    if read -t 10 -q "?Compress the log file? ([n]/y)"; then \
      zstd --rm --force --quiet "${file_wget_log}"; \
    fi; \
  }; \
  \
  trap cleanup INT TERM QUIT; \
  \
  : '# count and show in the terminal only unique "in-scope" URLs. NB: The sleep-interval option of "tail" set to 0 makes CPU run high'; \
  tail --lines=0 --sleep-interval=0.1 --follow='name' --retry "${file_wget_log}" \
    | awk --assign RS="\r?\n" ' \
        BEGINFILE                         { checked=0                                                                                  } \
        /^Queue count/                    { queued=$3; percent=sprintf("%.f", 100 - (100 * queued / (checked + queued + 0.01)))        } \
        /^--([0-9 -:]+)--  / && !a[$NF]++ { gsub(/&quot;\/?/, "", $NF); checked+=1; printf("%6d\t%3d%\t\t%s\n", checked, percent, $NF) }' & \
  \
  local -a wget_opts=(
    --regex-type=pcre
    --reject-regex=${reject_regex}
  ); \
  ( { wget \
        --debug \
        --directory-prefix="${TMPDIR:-/tmp}" \
        --no-directories \
        --spider \
        --recursive \
        --level='inf' \
        --page-requisites \
        --no-parent \
        "${reject_regex:+${wget_opts[@]}}" \
        "${address}" 2>&1 \
        || { local error_code=$?; \
             case "${error_code:-}" in \
               1) error_name='A GENERIC ERROR' ;; \
               2) error_name='A PARSE ERROR' ;; \
               3) error_name='A FILE I/O ERROR' ;; \
               4) error_name='A NETWORK FAILURE' ;; \
               5) error_name='A SSL VERIFICATION FAILURE' ;; \
               6) error_name='AN USERNAME/PASSWORD AUTHENTICATION FAILURE' ;; \
               7) error_name='A PROTOCOL ERROR' ;; \
               8) error_name='A SERVER ISSUED AN ERROR RESPONSE' ;; \
               *) error_name='AN UNKNOWN ERROR' ;; \
             esac; \
             if tail --lines=4 "${file_wget_log}" \
                  | grep --quiet --no-messages --word-regexp "FINISHED"; then \
               printf "\n%s\n" "--WGET SOFT-FAILED WITH ${error_name}${error_code:+" (code ${error_code})"}--" > /dev/tty; \
             else \
               mkfifo "${pipe_wget_tmp}"; \
               { tail --lines=40 "${file_wget_log}"; \
                 printf "\n%s\n%s\n\n" "--WGET FAILED WITH ${error_name} (code ${error_code})--" "Some last log entries are shown above"; \
               } > /dev/tty; \
             fi; \
           } \
    } \
        | tee "${file_wget_log}" \
            >(awk --assign RS="\r?\n" --assign IGNORECASE=1 ' \
                /^--([0-9 -:]+)--  /                              { url=$NF   } \
                /^HTTP\//                                         { code=$2   } \
                code ~ /200|204|206|304/ \
                  && $1 ~ /^Content-Type:/ \
                  && $2 ~ /^(text\/html|application\/xhtml\+xml)/ { print url }' \
                | grep --invert-match --ignore-case --basic-regexp --regexp='&quot;' \
                | sort --unique \
                | if_reject "${file_wget_sitemap}" \
             ) \
        | awk --assign RS="\r?\n" --assign OFS="\t" --assign address="${address}" ' \
            BEGIN                      { print address "\t"                                        } \
            /^--([0-9 -:]+)--  /       { email=""; referer=$NF                                     } \
            /^appending/               { gsub(/appending |[\047‘’]| to urlpos.|&quot;\/?/, ""); \
                                         gsub(/ /, "%20"); print $0, referer                       } \
            match($0, / -> mailto:.*/) { email=substr($0, RSTART+4, RLENGTH); print email, referer }' \
        | sort --key=1 --field-separator=$'\t' --unique > "${file_wget_links_refs}" \
        | cut --fields=1 \
            | sort --unique \
            | if [[ -n ${internal_only} ]]; then \
                grep --ignore-case --basic-regexp --regexp="^$(expr "${address}" : '\(.*://[^/]*\)')"; \
              elif [[ -n ${subtree_only} ]]; then \
                grep --ignore-case --basic-regexp --regexp="^${address}"; \
              else \
                cat; \
              fi \
            | if_reject "${file_wget_links}"; \
         \
    : 'if Wget did not hard-fail, show the stats'; \
    if [[ ! -p ${pipe_wget_tmp} ]]; then \
      cat <<-EOF
	$(tail --lines=4 "${file_wget_log}" | awk --assign RS="\r?\n" '/^Downloaded:/ { print $1, $4; next }; { print $0 }')
	Total links found: $(wc --lines < "${file_wget_links}")

	CREATED FILES
	$(du --human-readable "${file_wget_links}" "${file_wget_links_refs}" "${file_wget_sitemap}" "${file_wget_log}")

	EOF
      printf "\a"; \
      open "${folder}"; \
    fi; \
    \
    cleanup \
  ); \
  \
  setopt LOCAL_OPTIONS \
}
```

#### Resulting files:
- _PROJECT-NAME-wget-links.txt_ - list of all links found.
- _PROJECT-NAME-wget-links-and-refs.tsv_ - to be used at step 2.
- _PROJECT-NAME-wget-sitemap.txt_ - list of the html links found.
- _PROJECT-NAME-wget.log.zst_ - Wget log for debugging purposes.





## Step 2
Replace `PROJECT-NAME` with the same project name as above, and run:

```Shell
 : '# Check links using curl'; \
\
function { \
  \
  setopt LOCAL_TRAPS MONITOR MULTIOS; \
  unsetopt UNSET; \
  \
  SECONDS=0; \
  \
  : '# specify the project name'; \
  local project='PROJECT-NAME'; \
  \
  : '# specify additional HTTP codes (comma-separated) to exclude from the broken link report'; \
  local skip_code=''; \
  \
  : '# specify path for the resulting files'; \
  local folder="${HOME}/${project}"; \
  local file_wget_links="${folder}/${project}-wget-links.txt"; \
  local file_wget_links_refs="${folder}/${project}-wget-links-and-refs.tsv"; \
  local file_wget_sitemap="${folder}/${project}-wget-sitemap.txt"; \
  local file_curl_links="${folder}/${project}-curl-links.tsv"; \
  local file_curl_log="${folder}/${project}-curl.log"; \
  local file_broken_links="${folder}/${project}-broken-links-$(date +"%Y-%m-%d").tsv"; \
  \
  function cleanup() { \
    pkill -P $$ -x tail; sleep 1; \
    if [[ ! -s ${file_curl_links} ]]; then \
      rm --interactive='once' "${file_curl_links}"; \
    fi; \
    echo; \
    if read -t 30 -q "?Compress the log file? ([n]/y)"; then \
      zstd --rm --force --quiet "${file_curl_log}"; \
    fi; \
  }; \
  \
  trap cleanup INT TERM QUIT; \
  \
  : '# count and show in the terminal the URLs being checked. NB: The sleep-interval option of "tail" set to 0 makes CPU run high'; \
  tail --lines=0 --sleep-interval=0.1 --follow='name' --retry "${file_curl_log}" \
    | awk --assign RS="\r?\n" --assign total="$(wc --lines < "${file_wget_links}")" ' \
        BEGINFILE      { checked=0                                                                             } \
        /^time_total:/ { time_total=sprintf("%.2f", $2)                                                        } \
        /^END URL:/    { checked+=1; printf("%6d%s%-6d\t%s%s\t%s\n", checked, "/", total, time_total, "s", $3) }' & \
  \
  local -a curl_opts=(
    --disable
    --include
    --no-progress-meter
    --write-out
    '\nnum_redirects: %{num_redirects}\ntime_total: %{time_total}\n'
    --stderr
    -
    --location
    --referer
    ';auto'
  ); \
  ( while IFS=$'\n' read -r line; do \
      printf "%s\n" "START URL: ${line}"; \
        if grep --quiet --basic-regexp --regexp="^${line}$" "${file_wget_sitemap}"; then \
          curl \
            "${curl_opts[@]}" \
            --compressed \
            "${line}"; \
        elif grep --quiet --basic-regexp --regexp="^mailto:" <<< "${line}"; then \
          true; \
        else
          curl \
            "${curl_opts[@]}" \
            --head \
            "${line}"; \
        fi; \
        printf "%s\n\n" "END URL: ${line}"; \
    done < "${file_wget_links}" > "${file_curl_log}" \
      | awk --assign RS="\r?\n" --assign OFS="\t" --assign IGNORECASE=1 ' \
          BEGIN                       { print "URL", "CODE (LAST HOP IF REDIRECT)", "TYPE", "SIZE, KB", "REDIRECT", "NUM REDIRECTS", "TITLE", "og:title", "og:description" } \
          /^START URL:/               { url=$3; code=type=size=redirect=num_redirects=title=og_title=og_desc=""                                      } \
                                      { if (url ~ /^mailto:/) { \
                                          if (url ~ /[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,64}$/)
                                            { cmd="host -t MX $(cut -d@ -f2- <<<" url") | xargs"; cmd | getline mx_check; close(cmd); \
                                              if (mx_check ~ /mail is handled by [^0]/) \
                                                code="200 (MX found)"; \
                                              else \
                                                code=mx_check; \
                                            } \
                                          else \
                                            code="Bad email syntax"; \
                                          } \
                                        else if (/^HTTP\//) \
                                          code=$2; \
                                        else if (/^curl: \([0-9]{1,2}\)/) \
                                          code=$0;                                                                        
                                      } \
          /^Content-Length:/          { size=sprintf("%.f", $2 / 1024); (size != 0) ? size=size : size=1                                     } \
          /^Content-Type:/            { split($2, a, /;/); type=a[1]                                                                         } \
          /^Location:/                { redirect=$2                                                                                          } \
          /^num_redirects:/           { if ($2 != 0) num_redirects=$2                                                                        } \
          /<TITLE[^>]*>/,/<\/TITLE>/  { cmd="xmllint --html --xpath '\''//title/text()'\'' - 2> /dev/null <<< '\''"$0"'\''"; \
                                        cmd | getline title; \
                                        close(cmd); \
                                        gsub(/^[ \t]+|[ \t]+$/, "", title); \
                                        if (length(title) == 0) title="EMPTY TITLE" \
                                      } \
          /<META.*og:title/,/>/       { cmd="xmllint --html --xpath '\''string(//meta[@property=\"og:title\"]/@content)'\'' - 2> /dev/null <<< '\''"$0"'\''"; \
                                        cmd | getline og_title; \
                                        close(cmd) \
                                      } \
          /<META.*og:description/,/>/ { cmd="xmllint --html --xpath '\''string(//meta[@property=\"og:description\"]/@content)'\'' - 2> /dev/null <<< '\''"$0"'\''"; \
                                        cmd | getline og_desc; \
                                        close(cmd) \
                                      } \
          /^END URL:/                 { print url, code, type, size, redirect, num_redirects, title, og_title, og_desc                       }' \
      | { sed --unbuffered 1q; \
          sort --key=2 --field-separator=$'\t' --reverse; \
        } > "${file_curl_links}" \
        \
      && : '# infamously make sure the file has finished being written' \
      && sleep 2 \
      \
      && : '# now to the broken link report generation' \
      && local curl_links_error="$( { \
           awk --assign RS="\r?\n" --assign FS="\t" --assign OFS="\t" --assign skip="^(200${skip_code:+"|${skip_code//\,/|}"})" ' \
             $2 !~ 'skip' { print $1, $2 }' \
             | sort --key=1 --field-separator=$'\t'; \
           } < "${file_curl_links}" \
         )" \
      && if [[ $(wc --lines <<< "$curl_links_error") -gt 1 ]]; then
           awk --assign RS="\r?\n" --assign FS="\t" --assign OFS="\t" ' \
             BEGIN   { print "BROKEN LINK", "REFERER" } \
             NR==FNR { a[$1]++; next                  } \
             $1 in a { print $1, $2                   }' \
             <(printf "%s" "$curl_links_error") "${file_wget_links_refs}" \
                 | cat \
                     <(printf "S U M M A R Y\t\n") \
                     <(printf "%s" "$curl_links_error") \
                     <(printf "\nD E T A I L S\t\n") \
                     - > "${file_broken_links}"; \
         fi \
      \
      && cat <<-EOF

		FINISHED --$(date +"%F %T")--
		Total wall clock time: $((SECONDS / 3600))h $(((SECONDS / 60) % 60))m $((SECONDS % 60))s

		CREATED FILES
		$(du --human-readable "${file_curl_links}" "${file_curl_log}") (compressed)
		$(printf "\033[1m"
		  if [[ -f "${file_broken_links}" ]]; then
		    du --human-readable "${file_broken_links}"
		  else
		    printf "\nNo broken links found"
		  fi
		  printf "\033[0m"
		 )

	EOF
    printf "\a"; \
    sleep 0.3; \
    printf "\a"; \
    open "${folder}"; \
    \
    cleanup \
  ); \
  \
  setopt LOCAL_OPTIONS \
}
```

#### Resulting files:
- _PROJECT-NAME-broken-links-DD-MM-YYYY.tsv_ - list of the links with erroneous HTTP codes and referring URLs (see the picture above).
- _PROJECT-NAME-curl-links.tsv_ - list of all the links with HTTP codes and some other information.
- _PROJECT-NAME-curl.log.zst_ - curl log for debugging purposes.






## Version history
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
