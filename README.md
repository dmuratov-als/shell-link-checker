# Shell link checker
Website broken link checking shell (`#!/usr/bin/env zsh`) script based on **Wget** and **curl** with maximum user control over what is happening and how it is presented. The script consists of two one-liners (sort of) to be edited _ad hoc_, copied and pasted into the terminal, and run consecutively.

Most probably, one will need to fine-tune Wget and curl (such as set timeouts, include / exclude files, paths or domains, mimic a browser, handle HTTP or SSL errors, etc.) with options (consult the respective MAN pages) to get an adapted behavior.

### Prerequisites:
- `Wget` compiled with the "debug" flag and `libpcre` support
- `grep` compiled with `libpcre` support
- `curl`
- `awk`[^1]
- `coreutils`[^1]
- `pkill` (from the `procps` package)

[^1]: Did not test with BSD version, only GNU.

![Screenshot](/broken-links.jpg)

## Step 1
Replace `PROJECT-NAME` with the actual project name and `ADDRESS` with the URL to check, and run:

```Shell
 : 'Gather links using Wget' \
\
; set -o monitor -o multios -o nounset \
\
; : '# specify the project name' \
; project='PROJECT-NAME' \
\
; : '# specify the URL to check' \
; address='ADDRESS' \
\
; : '# specify a regexp (PCRE) to exclude paths or files. Make note that gawk uses GNU (?) ERE.' \
; reject_regex='' \
\
; : '# function to remove excluded links from the results' \
; function if_reject() { \
    if [[ -z ${reject_regex} ]]; then \
      > $1; \
    else \
      grep --invert-match --ignore-case --perl-regexp --regexp="${reject_regex}" 2> /dev/null \
        > $1; \
    fi \
  } \
\
; : '# paths and files' \
; folder="${HOME}/${project}" \
; if [[ ! -d "${folder}" ]]; then \
    mkdir "${folder}"; \
  fi \
; file_wget_links="${folder}/${project}-wget-links.txt" \
; file_wget_links_refs="${folder}/${project}-wget-links-and-refs.tsv" \
; file_wget_sitemap="${folder}/${project}-wget-sitemap.txt" \
; file_wget_log="${folder}/${project}-wget.log" \
; tmp_pipe=$(mktemp --dry-run --tmpdir="${TMPDIR:-/tmp}" 'wget_failed_XXX') \
\
; : '# help kill the background "tail" job, and remove unfinished files' \
; function cleanup() { \
    pkill -P $$ -x tail; \
    if [[ ! -s ${file_wget_links} && ${file_wget_links_refs} && ${file_wget_sitemap} ]]; then \
      rm --interactive='once' "${file_wget_links}" "${file_wget_links_refs}" "${file_wget_sitemap}"; \
      rm --interactive='once' --force "${tmp_pipe}"; \
    fi; \
    trap - INT QUIT; \
    set +o nounset; \
  } \
\
; : '# set the "cleanup" function to fire when pressed "Ctrl+C" or "CTRL+\"' \
; trap "cleanup" INT QUIT \
\
; : '# count and show in the terminal only unique "in-scope" URLs. NB: The sleep-interval option of "tail" set to 0 makes CPU run high' \
; tail --lines=0 --sleep-interval=0.1 --follow='name' --retry "${file_wget_log}" \
    | awk ' \
        BEGINFILE                        { count=0                                                               } \
        /^--([0-9 -:]+)--  / && !a[$3]++ { gsub(/&quot;\/?/, "", $3); count+=1; printf("%5d\t\t%s\n", count, $3) }' \
\
& ( { { wget \
          --debug \
          --directory-prefix="${TMPDIR:-/tmp}" \
          --no-directories \
          --spider \
          --recursive \
          --level='inf' \
          --page-requisites \
          $(env printf "%s" "${reject_regex:+"--regex-type=pcre --reject-regex=${reject_regex}"}") \
          "${address}" 2>&1 \
       && sleep 0.5; \
      } \
         || { error_code=$? \
              ; case "${error_code:-}" in \
                  1) error_name='A GENERIC ERROR' ;; \
                  2) error_name='A PARSE ERROR' ;; \
                  3) error_name='A FILE I/O ERROR' ;; \
                  4) error_name='A NETWORK FAILURE' ;; \
                  5) error_name='A SSL VERIFICATION FAILURE' ;; \
                  6) error_name='AN USERNAME/PASSWORD AUTHENTICATION FAILURE' ;; \
                  7) error_name='A PROTOCOL ERROR' ;; \
                  8) error_name='A SERVER ISSUED AN ERROR RESPONSE' ;; \
                  *) error_name='AN UNKNOWN ERROR' ;; \
              esac \
              ; sleep 0.5 \
              ; if tac "${file_wget_log}" \
                     | grep --quiet --no-messages --max-count=1 --word-regexp "FINISHED"; then \
                  env printf "\n%s\n" "--WGET SOFT-FAILED WITH ${error_name}${error_code:+" (code ${error_code})"}--" > /dev/tty; \
                else \
                  mkfifo "${tmp_pipe}" \
                  ; { tail --lines=40 "${file_wget_log}" \
                      ; env printf "\n%s\n\n" "--WGET FAILED WITH ${error_name} (code ${error_code})--" \
                  ; } > /dev/tty; \
                fi; \
            } \
    } \
       | tee "${file_wget_log}" \
           >(awk -v BINMODE=rw -v IGNORECASE=1 ' \
               /^--([0-9 -:]+)--  / && !/.*\.js|.*\.css|.*\.ico|.*\.jpg|.*\.jpeg|.*\.png|.*\.gif|.*\.svg|.*\.tif|.*\.tiff|.*\.mp3|.*\.mp4|.*\.ogg|.*\.webm|.*\.webp|.*\.flv|.*\.swf|.*\.pdf|.*\.rtf|.*\.doc|.*\.docx|.*\.xls|.*\.xlsx|.*\.ppt|.*\.xml|.*\.txt|.*\.zip|.*\.rar|.*\.ics|.*\.woff|.*\.woff2|.*\.ttf|.*\.eot|.*\.cur|.*\.webmanifest/ { gsub(/&quot;\/?/, "", $3); print $3 }' \
               | sort --unique \
               | if_reject "${file_wget_sitemap}" \
            ) \
       | awk -v OFS="\t" -v BINMODE=rw ' \
           /^--([0-9 -:]+)--  / { sub($1 " " $2 "  ", ""); REFERER=$0                   } \
           /^appending/         { gsub(/[\047‘’]|&quot;\/?/, "", $2); print $2, REFERER }' \
       | sort --key=1 --field-separator=$'\t' --unique \
           > "${file_wget_links_refs}" \
       | cut --fields=1 \
           | sort --unique \
           | if_reject "${file_wget_links}" \
       \
     ; : 'if Wget did not hard-fail, show the stats'
     ; if [[ ! -p ${tmp_pipe} ]]; then \
         : '# show Wget statistics' \
         ; tail --lines=4 "${file_wget_log}" \
             | awk '/^Downloaded:/ { print $1, $4; next }; { print $0 }' \
         \
         ; : '# show the number of links' \
         ; env printf "%s%s" 'Total links found: ' "$(wc --lines < "${file_wget_links}")" \
         \
         ; : '# show the created files' \
         ; env printf "\n\n%s\n%s\n\n" 'CREATED FILES' "$(du --human-readable "${file_wget_links}" "${file_wget_links_refs}" "${file_wget_sitemap}" "${file_wget_log}")" \
         \
         ; : 'ring the bell' \
         ; env printf "\a"; \
       fi \
       ; : 'fire the "cleanup" function' \
       ; cleanup \
  )
```

#### Resulting files:
- _PROJECT-NAME-wget-links.txt_ - list of all links found.
- _PROJECT-NAME-wget-links-and-refs.tsv_ - to be used at step 2.
- _PROJECT-NAME-wget-sitemap.txt_ - list of the html links found.
- _PROJECT-NAME-wget.log_ - Wget log for debugging purposes.





## Step 2
Replace `PROJECT-NAME` with the same project name as above, and run:

```Shell
 : 'Check links using curl' \
\
; set -o monitor -o multios -o nounset \
; SECONDS=0 \
\
; : '# specify the project name' \
; project='PROJECT-NAME' \
\
; : '# paths and files' \
; folder="${HOME}/${project}" \
; file_wget_links="${folder}/${project}-wget-links.txt" \
; file_wget_links_refs="${folder}/${project}-wget-links-and-refs.tsv" \
; file_curl_links="${folder}/${project}-curl-links.tsv" \
; file_curl_log="${folder}/${project}-curl.log" \
; file_broken_links="${folder}/${project}-broken-links-$(date +"%d-%m-%Y").tsv" \
\
; : '# help kill the background "tail" job, and remove unfinished files' \
; function cleanup() { \
    pkill -P $$ -x tail; \
    if [[ ! -s ${file_curl_links} ]]; then
      rm --interactive='once' "${file_curl_links}";
    fi; \
    trap - INT QUIT; \
    set +o nounset; \
  } \
\
; : '# set the "cleanup" function to fire when pressed "Ctrl+C" or "CTRL+\"' \
; trap "cleanup" INT QUIT \
\
; : '# count and show in the terminal the URLs being checked. NB: The sleep-interval option of "tail" set to 0 makes CPU run high' \
; tail --lines=0 --sleep-interval=0.1 --follow='name' --retry "${file_curl_log}" \
    | awk -v total="$(wc --lines < "${file_wget_links}")" ' \
        BEGINFILE      { count=0                                                                     } \
        /^time_total:/ { time_total=sprintf("%.2f", $2)                                              } \
        /^END URL:/    { count+=1; printf("%5d%s%-5d\t%ss\t%s\n", count, "/", total, time_total, $3) }' \
& ( while IFS=$'\n' read -r line ; do \
      env printf "%s\n" "START URL: ${line}" \
      ; curl \
          --verbose \
          --no-progress-meter \
          --write-out 'num_redirects: %{num_redirects}\ntime_total: %{time_total}\n' \
          --stderr - \
          --head \
          --location \
          --referer ';auto' \
          "${line}" \
      ; env printf "%s\n\n" "END URL: ${line}"; \
    done < "${file_wget_links}" \
      \
      > "${file_curl_log}" \
      | awk -v RS="\r?\n" -v OFS="\t" -v BINMODE=rw -v IGNORECASE=1 ' \
          BEGIN                   { print "URL", "CODE (LAST HOP IF REDIRECT)", "TYPE", "LENGTH, KB", "REDIRECT", "NUM REDIRECTS" } \
          /^START URL:/           { URL=$3; CODE=LENGTH=TYPE=LOCATION=NUM_REDIRECTS=""                                            } \
          /^HTTP\//               { CODE=$2                                                                                       } \
          /^curl: \([0-9]{1,2}\)/ { CODE=$0                                                                                       } \
          /^Content-Length:/      { if ($2 != 0) LENGTH=sprintf("%.f", $2 /1024)                                                  } \
          /^Content-Type:/        { split($2, a, /;/); TYPE=a[1]                                                                  } \
          /^Location:/            { LOCATION=$2                                                                                   } \
          /^num_redirects:/       { if ($2 != 0) NUM_REDIRECTS=$2                                                                 } \
          /^END URL:/             { print URL, CODE, TYPE, LENGTH, LOCATION, NUM_REDIRECTS                                        }' \
      | { sed --unbuffered 1q \
            ; sort --key=2 --field-separator=$'\t' --reverse; } \
                > "${file_curl_links}" \
      \
      && : '# infamously make sure the file has finished being written' \
      && sleep 0.5 \
      \
      && : '# now to the broken link report generation' \
      && curl_links_error="$( { \
           awk -v FS="\t" -v OFS="\t" -v BINMODE=rw ' \
             $2 !~ /^200/ { print $1, $2 }' \
               | sort --key=1 --field-separator=$'\t'; } \
           < "${file_curl_links}" \
         )" \
      && awk -v FS="\t" -v OFS="\t" -v BINMODE=rw ' \
           BEGIN   { print "BROKEN LINK", "REFERER" } \
           NR==FNR { a[$1]++; next                  } \
           $1 in a { print $1, $2                   }' \
           <(env printf "%s" "$curl_links_error") "${file_wget_links_refs}" \
             | cat \
                 <(env printf "%s\t\n" 'S U M M A R Y') \
                 <(env printf "%s" "$curl_links_error") \
                 <(env printf "\n%s\t\n" 'D E T A I L S') \
                 - \
                   > "${file_broken_links}" \
      \
      && : '# show the elapsed time' \
      && env printf "\n%s%s%s\n" 'FINISHED --' "$(date +"%F %T")" '--' \
      && env printf "%s%s\n" 'Total wall clock time: ' "$((SECONDS / 3600))h $(((SECONDS / 60) % 60))m $((SECONDS % 60))s" \
      \
      && : '# show the created files' \
      && env printf "\n%s\n%s\n%b%s%b\n\n" 'CREATED FILES' "$(du --human-readable "${file_curl_links}" "${file_curl_log}")" "\033[1m" "$(du --human-readable "${file_broken_links}")" "\033[0m" \
      \
      && : 'ring the bell' \
      && env printf "\a" \
      && sleep 0.4 \
      && env printf "\a" \
      \
      ; : 'fire the "cleanup" function' \
      ; cleanup \
  )
```

#### Resulting files:
- _PROJECT-NAME-broken-links-DD-MM-YYYY.tsv_ - list of the links with erroneous HTTP codes and referring URLs (see the picture above).
- _PROJECT-NAME-curl-links.tsv_ - list of all the links with HTTP codes and some other information.
- _PROJECT-NAME-curl.log_ - curl log for debugging purposes.






## Version history
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
