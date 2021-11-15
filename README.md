# Shell link checker
Website broken link checking shell script based on **Wget** and **curl** with maximum user control over what is happening and how it is presented. The script consists of three one-liners to be edited _ad hoc_, copied and pasted into the terminal, and run consecutively.

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
varProject="PROJECT-NAME" \
; varAddress="ADDRESS" \
; funcCleanup() { set +m; pkill -P $$ -x tail; } \
; trap "funcCleanup" INT \
; tail --lines=+1 --follow=name --retry "$HOME/$varProject-wget-log.txt" | awk '/[0-9]--  / { print $0 }' \
& wget \
	--debug \
	--no-directories \
	--spider \
	--recursive \
	--level=inf \
	--page-requisites \
	"$varAddress" 2>&1 \
| dos2unix \
| tee "$HOME/$varProject-wget-log.txt" \
| awk -v BINMODE=2 ' \
	BEGIN		{ OFS="\t" } \
	/[0-9]--  /	{ sub($1" "$2"  ", ""); REFERER=$0 } \
	/^appending /	{ gsub(/\047|‘|’/, "", $2); print $2, REFERER } \
	END		{ OFS="\n" }' \
| sort --key=1 --field-separator="$(printf '\t')" | uniq \
| tee \
	>(cut --fields=1 | sort | uniq > "$HOME/$varProject-wget-links.txt") \
| tee "$HOME/.$varProject-wget-links-and-refs.csv" > /dev/null \
; funcCleanup \
&& tail --lines=4 "$HOME/$varProject-wget-log.txt" \
&& tput bel
```

#### Resulting files:
- _PROJECT-NAME-wget-log.txt.gz_ - Wget log for debugging purposes.
- _PROJECT-NAME-wget-links.txt_ - list of all links found.
- _.PROJECT-NAME-wget-links-and-refs.csv_ - to be used at step 3.





## Step 2
Replace `PROJECT-NAME` with the same project name as above, and run:

```Shell
varProject="PROJECT-NAME" \
; funcCleanup() { set +m; pkill -P $$ -x tail; } \
; trap "funcCleanup" INT \
; tail --lines=+1 --follow=name --retry "$HOME/$varProject-curl-log.txt" | awk '/START URL:/ { print $3 }' \
& while read -r varLine ; do \
	printf "%s\n" "START URL: $varLine"; \
	curl \
		--verbose \
		--silent \
		--show-error \
		--head \
		--location \
		"$varLine"; \
	printf "%s\n\n" "END URL: $varLine"; \
done < "$HOME/$varProject-wget-links.txt" 2>&1 \
| dos2unix \
| tee "$HOME/$varProject-curl-log.txt" \
| awk -v BINMODE=2 ' \
	BEGIN					{ OFS="\t"; print "URL", "CODE (LAST HOP IN CASE OF REDIRECT)", "TYPE", "LENGTH", "REDIRECT" } \
	/^START URL:/				{ URL=$3; CODE=LENGTH=TYPE=LOCATION=""	; next } \
	/^HTTP\// || /^curl: \([0-9]{1,2}\)/	{ sub($1" ", ""); CODE=$0		; next } \
	/^Content-Length:/			{ OFMT="%.1f"; LENGTH=$2/1024		; next } \
	/^Content-Type:/			{ split($2, a, /;/); TYPE=a[1]		; next } \
	/^Location:/				{ LOCATION=$2				; next } \
	/^END URL:/				{ print URL, CODE, TYPE, LENGTH, LOCATION }' \
| (gsed --unbuffered 1q; sort --key=2 --field-separator="$(printf '\t')" --reverse) \
| tee "$HOME/$varProject-curl-links.csv" \
| awk -v BINMODE=2 ' \
	BEGIN		{ FS=OFS="\t" } \
	$2 !~ /^200/	{ print $1, $2 }' \
| sort --key=1 --field-separator="$(printf '\t')" > "$HOME/.$varProject-curl-links-error.csv" \
; funcCleanup \
&& tput bel
```

#### Resulting files:
- _PROJECT-NAME-curl-log.txt_ - curl log for debugging purposes.
- _PROJECT-NAME-curl-links.csv_ - list of all the links with HTTP codes and some other information.
- _.PROJECT-NAME-curl-links-error.csv_ - to be used at step 3.





## Step 3
Replace `PROJECT-NAME` with the same project name as above, and run:

```Shell
varProject="PROJECT-NAME" \
; awk -v BINMODE=2 ' \
	BEGIN		{ FS=OFS="\t"; print "BROKEN LINK", "REFERER" } \
	NR==FNR		{ c[$1]++; next }; \
	$1 in c		{ print $1, $2 }' \
	"$HOME/.$varProject-curl-links-error.csv" \
	"$HOME/.$varProject-wget-links-and-refs.csv" \
| cat \
	<(printf "%s\n" "S U M M A R Y") "$HOME/.$varProject-curl-links-error.csv" \
	<(printf "\n%s\n" "D E T A I L S") - \
	> "$HOME/$varProject-broken-links-$(date +"%d-%m-%Y").csv"
```

#### Resulting file:
- _PROJECT-NAME-broken-links-DD-MM-YYYY.csv_ - list of the links with erroneous HTTP codes and referring URLs (see the picture above).

## Version history
#### v1.1.1
- The URLs the script is working on are now shown in the terminal
- Wget statistics upon finishing the retrieval is moved from the file into the terminal
- Wget log file is no longer compressed to keep it readable in case of script's premature exit

#### v1.0.0
Initial release
