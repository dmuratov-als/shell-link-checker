# Shell link checker
Website broken link checking shell (`#!/usr/bin/env zsh`) script based on **Wget** and **curl** with maximum user control over what is happening and how it is presented. The script consists of two one-liners (sort of) to be edited _ad hoc_, copied and pasted into the terminal, and run consecutively.

Most probably, one will need to fine-tune Wget and curl (such as set timeouts, include / exclude files, paths or domains, mimic a browser, handle HTTP or SSL errors, etc.) with options (consult the respective MAN pages) to get an adapted behavior.

### Main requirements:
- Wget compiled with the "debug" flag and libpcre support
- grep compiled with libpcre support
- curl
- awk[^1]
- coreutils[^1]
- dos2unix

[^1]: Did not test with BSD version, only GNU.

![Screenshot](/broken-links.jpg)

## Step 1
Replace `PROJECT-NAME` with the actual project name and `ADDRESS` with the URL to check, and run:

```Shell
 set -o monitor -o nounset \
\
; : '# specify the project name' \
; project="PROJECT-NAME" \
\
; : '# specify the URL to check' \
; address="ADDRESS" \
\
; : '# specify a regexp (PCRE) if needed ' \
; reject_regex="" \
\
; : '# paths and files' \
; folder="" \
; file_wget_links="${HOME}${folder}/${project}-wget-links.txt" \
; file_wget_links_refs="${HOME}${folder}/.${project}-wget-links-and-refs.csv" \
; file_wget_log="${HOME}${folder}/${project}-wget.log" \
\
; : '# help kill the background "tail" job, and remove empty files' \
; func_cleanup() { \
    pkill -P $$ -x tail \
    ; if [[ ! -s ${file_wget_links} && ${file_wget_links_refs} ]]; then \
        rm --interactive="once" "${file_wget_links}" "${file_wget_links_refs}"; \
      fi; \
  } \
\
; : '# set "func_cleanup" to fire when pressed "Ctrl+C" or "CTRL+\"' \
; trap "func_cleanup" INT QUIT \
\
; : '# count and show in the terminal only unique "in-scope" URLs. NB: The sleep-interval option of "tail" set to 0 makes CPU run high; the "dos2unix" output stream should be unbuffered to display URLs one by one.' \
; tail --lines=0 --sleep-interval=0.1 --follow=name --retry "${file_wget_log}" \
    | awk -v BINMODE=r ' \
        BEGINFILE                           { count=0                                 } \
        /^--([0-9 -:]+)--  / && ! a[$3]++   { count+=1; print count "\t" $3; fflush() }' \
\
& ( { wget \
        --debug \
        --directory-prefix="${TMPDIR:-/tmp}" \
        --no-directories \
        --spider \
        --recursive \
        --level=inf \
        --page-requisites \
        `env printf "%s" "${reject_regex:+--regex-type=pcre --reject-regex="${reject_regex}"}"` \
        "${address}" 2>&1 \
      && sleep 0.5; \
    } \
      \
        | stdbuf -oL dos2unix --quiet \
            > "${file_wget_log}" \
        | awk -v BINMODE=rw ' \
            BEGIN                   { OFS="\t"                                    } \
            /^--([0-9 -:]+)--  /    { sub($1 " " $2 "  ", ""); REFERER=$0         } \
            /^appending/            { gsub(/[\047‘’]/, "", $2); print $2, REFERER } \
            END                     { OFS="\n"                                    }' \
        | sort --key=1 --field-separator="$(env printf '\t')" \
        | uniq \
            > "${file_wget_links_refs}" \
        | cut --fields=1 \
            | sort \
            | uniq \
            | if [[ -z ${reject_regex} ]]; then \
                > "${file_wget_links}"; \
              else \
                grep --invert-match --ignore-case --perl-regexp --regexp="${reject_regex}" \
                  > "${file_wget_links}"; \
              fi \
        \
        && : '# show Wget statistics (except the last meaningless line) upon pipe exit' \
        && tail --lines=4 "${file_wget_log}" \
             | sed '$d' \
        \
        && : '# show the number of links' \
        && env printf "%s" "Total links found: " \
             && wc --lines < "${file_wget_links}" \
        \
        && : '# show the created files' \
        && env printf "\n%s\n" "CREATED FILES" \
             && du --human-readable "${file_wget_links}" "${file_wget_links_refs}" "${file_wget_log}" \
        \
        && : 'ring the bell' \
        && env printf "\a" \
        \
        ; : 'fire "func_cleanup"' \
        ; func_cleanup \
  )
```

#### Resulting files:
- _PROJECT-NAME-wget-links.txt_ - list of all links found.
- _.PROJECT-NAME-wget-links-and-refs.csv_ - to be used at step 2.
- _PROJECT-NAME-wget.log_ - Wget log for debugging purposes.





## Step 2
Replace `PROJECT-NAME` with the same project name as above, and run:

```Shell
 set -o monitor -o nounset \
; SECONDS=0 \
\
; : '# specify the project name' \
; project="PROJECT-NAME" \
\
; : '# paths and files' \
; folder="" \
; file_wget_links="${HOME}${folder}/${project}-wget-links.txt" \
; file_wget_links_refs="${HOME}${folder}/.${project}-wget-links-and-refs.csv" \
; file_curl_links="${HOME}${folder}/${project}-curl-links.csv" \
; file_curl_links_error="${HOME}${folder}/.${project}-curl-links-error.csv" \
; file_curl_log="${HOME}${folder}/${project}-curl.log" \
; file_broken_links="${HOME}${folder}/${project}-broken-links-$(date +"%d-%m-%Y").csv" \
\
; : '# help kill the background "tail" job, and remove empty files' \
; func_cleanup() { \
    pkill -P $$ -x tail; \
    if [[ ! -s ${file_curl_links} && ${file_curl_links_error} ]]; then
      rm --interactive="once" "${file_curl_links}" "${file_curl_links_error}";
    fi; \
  } \
\
; : '# set "func_cleanup" to fire when pressed "Ctrl+C" or "CTRL+\"' \
; trap "func_cleanup" INT QUIT \
\
; : '# count and show in the terminal the URLs being checked. NB: The sleep-interval option of "tail" set to 0 makes CPU run high; the "dos2unix" output stream should be unbuffered to display URLs one by one.' \
; tail --lines=0 --sleep-interval=0.1 --follow=name --retry "${file_curl_log}" \
    | awk -v BINMODE=r ' \
        BEGINFILE    { count=0                                 } \
        /START URL:/ { count+=1; print count "\t" $3; fflush() }' \
& ( while read -r line ; do \
      env printf "%s\n" "START URL: ${line}" \
      ; curl \
          --verbose \
          --silent \
          --show-error \
          --head \
          --location \
          "${line}" \
      ; env printf "%s\n\n" "END URL: ${line}"; \
    done < "${file_wget_links}" 2>&1 \
      \
      | stdbuf -oL dos2unix --quiet \
          > "${file_curl_log}" \
      | awk -v BINMODE=rw ' \
          BEGIN                                { OFS="\t"; print "URL", "CODE (LAST HOP IN CASE OF REDIRECT)", "TYPE", "LENGTH", "REDIRECT"  } \
          /^START URL:/                        { URL=$3; CODE=LENGTH=TYPE=LOCATION=""                                                        } \
          /^HTTP\// || /^curl: \([0-9]{1,2}\)/ { sub($1 " ", ""); CODE=$0                                                                    } \
          /^Content-Length:/                   { OFMT="%.1f"; LENGTH=$2/1024                                                                 } \
          /^Content-Type:/                     { split($2, a, /;/); TYPE=a[1]                                                                } \
          /^Location:/                         { LOCATION=$2                                                                                 } \
          /^END URL:/                          { print URL, CODE, TYPE, LENGTH, LOCATION                                                     }' \
      | { sed --unbuffered 1q \
            ; sort --key=2 --field-separator="$(env printf '\t')" --reverse; } \
                > "${file_curl_links}" \
      | awk -v BINMODE=rw ' \
          BEGIN        { FS=OFS="\t"  } \
          $2 !~ /^200/ { print $1, $2 }' \
      | sort --key=1 --field-separator="$(env printf '\t')" \
          > "${file_curl_links_error}" \
      \
      && : '# infamously make sure all the files have finished being written' \
      && sleep 0.5 \
      \
      && : '# now to the broken link report generation' \
      && awk -v BINMODE=rw ' \
           BEGIN     { FS=OFS="\t"; print "BROKEN LINK", "REFERER" } \
           NR==FNR   { c[$1]++; next                               } \
           $1 in c   { print $1, $2                                }' \
           "${file_curl_links_error}" "${file_wget_links_refs}" \
           | cat \
               <(env printf "%s\t\n" "S U M M A R Y") "${file_curl_links_error}" \
               <(env printf "\n%s\t\n" "D E T A I L S") - \
                   > "${file_broken_links}" \
      \
      && : '# show the elapsed time and the created files' \
      && env printf "\n%s\n" "FINISHED --$(date +"%F %T")--" \
      && env printf "%s\n" "Total wall clock time: $(($SECONDS / 3600))h $((($SECONDS / 60) % 60))m $(($SECONDS % 60))s" \
      && env printf "\n%s\n" "CREATED FILES" \
           && du --human-readable "${file_curl_links}" "${file_curl_links_error}" "${file_curl_log}" \
      \
      && : '# show the report file path' \
      && env printf "%b\t" "\033[1m""\nBROKEN LINK REPORT\n"$(du --human-readable "${file_broken_links}")"\033[0m" \
      \
      && : 'ring the bell' \
      && env printf "\a" \
      \
      ; : 'fire "func_cleanup"' \
      ; func_cleanup \
  )
```

#### Resulting files:
- _PROJECT-NAME-broken-links-DD-MM-YYYY.csv_ - list of the links with erroneous HTTP codes and referring URLs (see the picture above).
- _PROJECT-NAME-curl-links.csv_ - list of all the links with HTTP codes and some other information.
- _.PROJECT-NAME-curl-links-error.csv_
- _PROJECT-NAME-curl.log_ - curl log for debugging purposes.






## Version history
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
