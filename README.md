# Shell link checker
Website broken link checking shell (`#!/bin/sh`) script based on **Wget** and **curl** with maximum user control over what is happening and how it is presented. The script consists of two one-liners (sort of) to be edited _ad hoc_, copied and pasted into the terminal, and run consecutively.

Most probably, one will need to fine-tune Wget and curl (such as set timeouts, include / exclude files, paths or domains, mimic a browser, handle HTTP or SSL errors, etc.) with options (consult the respective MAN pages) to get an adapted behavior.

#### Main requirements:
- Wget compiled with the "debug" flag
- curl
- awk[^1]
- coreutils[^1]
- dos2unix (can be replaced with _tr_ or the like)

[^1]: Did not test with BSD version, only GNU.

![Screenshot](/broken-links.jpg)

## Step 1
Replace `PROJECT-NAME` with the actual project name and `ADDRESS` with the URL to check, and run:

```Shell
set -u \
; project="PROJECT-NAME" \
; address="ADDRESS" \
; folder="" \
; file_wget_links="${HOME}${folder}/${project}-wget-links.txt" \
; file_wget_links_refs="${HOME}${folder}/.${project}-wget-links-and-refs.csv" \
; file_wget_log="${HOME}${folder}/${project}-wget.log" \
; : '# kill the background "tail" job and hide the termination message' \
; func_cleanup() { \
    set +m \
    ; pkill -P $$ -x tail; } \
; : '# set "func_cleanup" to fire when pressed "Ctrl+C" or "CTRL+\"' \
; trap "func_cleanup" INT QUIT \
; : '# show the retrieved URLs in the terminal' \
; tail --lines=0 --follow=name --retry "${file_wget_log}" \
  | awk '/[0-9]--  / { print $0 }' \
& wget \
    --debug \
    --no-directories \
    --spider \
    --recursive \
    --level=inf \
    --page-requisites \
    "${address}" 2>&1 \
| dos2unix \
| tee "${file_wget_log}" \
| awk -v BINMODE=2 ' \
    BEGIN         { OFS="\t"                                    } \
    /[0-9]--  /   { sub($1" "$2"  ", ""); REFERER=$0            } \
    /^appending / { gsub(/\047|‘|’/, "", $2); print $2, REFERER } \
    END           { OFS="\n"                                    }' \
| sort --key=1 --field-separator="$(printf '\t')" \
  | uniq \
| tee \
    >(cut --fields=1 \
      | sort \
      | uniq > "${file_wget_links}") \
| tee "${file_wget_links_refs}" > /dev/null \
&& : '# fire "func_cleanup" upon pipe exit...' \
&& func_cleanup \
&& : '# and show statistics and ring the bell' \
&& tail --lines=4 "${file_wget_log}" \
&& wc --lines "${file_wget_links}" \
   | awk '{ print "Links found: " $1 }' \
&& printf "\a" \
; : '# always show the created files' \
; printf "\n%s\n" "Created files:" \
&& du --human-readable "${file_wget_links}" "${file_wget_links_refs}" "${file_wget_log}"
```

#### Resulting files:
- _PROJECT-NAME-wget-links.txt_ - list of all links found.
- _.PROJECT-NAME-wget-links-and-refs.csv_ - to be used at step 2.
- _PROJECT-NAME-wget-log.txt.gz_ - Wget log for debugging purposes.





## Step 2
Replace `PROJECT-NAME` with the same project name as above, and run:

```Shell
set -u \
; project="PROJECT-NAME" \
; folder="" \
; file_wget_links="${HOME}${folder}/${project}-wget-links.txt" \
; file_wget_links_refs="${HOME}${folder}/.${project}-wget-links-and-refs.csv" \
; file_curl_links="${HOME}${folder}/${project}-curl-links.csv" \
; file_curl_links_error="${HOME}${folder}/.${project}-curl-links-error.csv" \
; file_curl_log="${HOME}${folder}/${project}-curl.log" \
; file_broken_links="${HOME}${folder}/${project}-broken-links-$(date +"%d-%m-%Y").csv" \
; : '# kill the background "tail" job and hide the termination message' \
; func_cleanup() { \
    set +m \
    ; pkill -P $$ -x tail; } \
; : '# set "func_cleanup" to fire when pressed "Ctrl+C" or "CTRL+\"' \
; trap "func_cleanup" INT QUIT \
; : '# show the checked URLs in the terminal' \
; tail --lines=0 --follow=name --retry "${file_curl_log}" \
  | awk '/START URL:/ { print $3 }' \
& while read -r line ; do \
    printf "%s\n" "START URL: ${line}" \
    ; curl \
        --verbose \
        --silent \
        --show-error \
        --head \
        --location \
      "${line}" \
    ; printf "%s\n\n" "END URL: ${line}"; \
done < "${file_wget_links}" 2>&1 \
| dos2unix \
| tee "${file_curl_log}" \
| awk -v BINMODE=2 ' \
    BEGIN                                { OFS="\t"; print "URL", "CODE (LAST HOP IN CASE OF REDIRECT)", "TYPE", "LENGTH", "REDIRECT" } \
    /^START URL:/                        { URL=$3; CODE=LENGTH=TYPE=LOCATION=""                                                       } \
    /^HTTP\// || /^curl: \([0-9]{1,2}\)/ { sub($1" ", ""); CODE=$0                                                                    } \
    /^Content-Length:/                   { OFMT="%.1f"; LENGTH=$2/1024                                                                } \
    /^Content-Type:/                     { split($2, a, /;/); TYPE=a[1]                                                               } \
    /^Location:/                         { LOCATION=$2                                                                                } \
    /^END URL:/                          { print URL, CODE, TYPE, LENGTH, LOCATION                                                    }' \
| (sed --unbuffered 1q \
   ; sort --key=2 --field-separator="$(printf '\t')" --reverse) \
| tee "${file_curl_links}" \
| awk -v BINMODE=2 ' \
    BEGIN        { FS=OFS="\t"  } \
    $2 !~ /^200/ { print $1, $2 }' \
| sort --key=1 --field-separator="$(printf '\t')" > "${file_curl_links_error}" \
&& : '# fire "func_cleanup" upon pipe exit' \
&& func_cleanup \
&& : '# infamously make sure the files have finished being written' \
&& sleep 2 \
&& : '# broken link report generation' \
&& awk -v BINMODE=2 ' \
     BEGIN   { FS=OFS="\t"; print "BROKEN LINK", "REFERER" } \
     NR==FNR { c[$1]++; next                               }; \
     $1 in c { print $1, $2                                }' \
     "${file_curl_links_error}" "${file_wget_links_refs}" \
| cat \
    <(printf "%s\n" "S U M M A R Y") "${file_curl_links_error}" \
    <(printf "\n%s\n" "D E T A I L S") - > "${file_broken_links}" \
&& : '# show the report file path and ring the bell' \
&& _file_broken_links_stat=$(du --human-readable "${file_broken_links}") \
&& printf "\n%b\n" "\033[1m""Broken link report:\n"${_file_broken_links_stat}"\033[0m" \
&& printf "\a" \
; : '# always show the created files' \
; printf "\n%s\n" "Created files:"
; du --human-readable "${file_curl_links}" "${file_curl_links_error}" "${file_curl_log}"
```

#### Resulting files:
- _PROJECT-NAME-broken-links-DD-MM-YYYY.csv_ - list of the links with erroneous HTTP codes and referring URLs (see the picture above).
- _PROJECT-NAME-curl-links.csv_ - list of all the links with HTTP codes and some other information.
- _.PROJECT-NAME-curl-links-error.csv_
- _PROJECT-NAME-curl-log.txt_ - curl log for debugging purposes.






## Version history
#### v1.2.2
- the three scripts are combined into two
- added more statictics

#### v1.1.1
- The URLs the script is working on are now shown in the terminal
- Wget statistics upon finishing the retrieval is moved from the file into the terminal
- Wget log file is no longer compressed to keep it readable in case of script's premature exit

#### v1.0.0
Initial release
