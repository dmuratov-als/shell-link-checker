# Shell link checker
Website link checking shell script based on **Wget** and **curl** (utilizing HEAD method when possible to save bandwidth) with maximum user control over what is happening and how it is presented. The script consists of three one-liners to be edited _ad hoc_, copied and pasted into the terminal, and run consecutively.

Most probably, one will need to fine-tune Wget and curl (such as set timeouts, include / exclude domains or paths, mimic a browser, handle HTTP or SSL errors, enable compression, etc.) using available options to get the adapted behavior. The options given below are those _sine qua non_.

#### Main prerequisites:
- Wget compiled with the "debug" flag
- curl
- awk[^1]
- coreutils[^1]
- dos2unix (can be replaced with tr or the like)

[^1]: Did not test with BSD version, only GNU.

![Screenshot](/broken-links.jpg)

## Step 1
Replace `[PROJECT-NAME]` with the actual project name and `[ADDRESS]` with the URL to check, and run:

```Shell
PROJECT="[PROJECT-NAME]"; \
ADDRESS="[ADDRESS]"; \
wget \
	--debug \
	--no-directories \
	--spider \
	--recursive \
	--level=inf \
	--page-requisites \
	$ADDRESS 2>&1 \
| dos2unix \
| tee >(gzip > "$HOME/$PROJECT-wget-log.txt.gz") \
| awk -v BINMODE=2 ' \
	BEGIN			{ OFS="\t" } \
	/[0-9]--  /		{ sub($1" "$2"  ", ""); REFERER=$0 } \
	/^appending /		{ gsub(/\047/, "", $2); print $2, REFERER } \
	END			{ OFS="\n" } \
	/^FINISHED --[0-9]/, 0	{ print "\n" $0 } \
' \
| sort --key=1 --field-separator="$(printf '\t')" | uniq \
| tee >(cut --fields=1 --only-delimited | sort | uniq > "$HOME/$PROJECT-wget-links.txt") \
| tee "$HOME/.$PROJECT-wget-links-and-refs.csv" \
&& tput bel
```

#### Resulting files:
- _[PROJECT-NAME]-wget-log.txt.gz_ - Wget log (compressed by default as it often gets large) for debugging purposes.
- _[PROJECT-NAME]-wget-links.txt_ - list of all links found.
- _.[PROJECT-NAME]-wget-links-and-refs.csv_ - used at step 3.





## Step 2
Replace `[PROJECT-NAME]` with the same project name as above, and run:

```Shell
PROJECT="[PROJECT-NAME]"; \
while read -r LINE ; do \
	printf "%s\n" "START URL: $LINE"; \
	curl \
		--verbose \
		--silent \
		--show-error \
		--head \
		--location \
		$LINE; \
	printf "%s\n\n" "END URL: $LINE"; \
done < "$HOME/$PROJECT-wget-links.txt" 2>&1 \
| dos2unix \
| tee "$HOME/$PROJECT-curl-log.txt" \
| awk -v BINMODE=2 ' \
	BEGIN					{ OFS="\t"; print "URL", "CODE (LAST HOP IN CASE OF REDIRECT)", "TYPE", "LENGTH", "REDIRECT" } \
	/^START URL:/				{ URL=$3; CODE=TYPE=LENGTH=LOCATION=""	; next } \
	/^HTTP\// || /^curl: \([0-9]{1,2}\)/	{ sub($1" ", ""); CODE=$0		; next } \
	/^Content-Length:/			{ OFMT="%.1f"; LENGTH=$2/1024		; next } \
	/^Content-Type:/			{ split($2, a, /;/); TYPE=a[1]		; next } \
	/^Location:/				{ LOCATION=$2				; next } \
	/^END URL:/				{ print URL, CODE, TYPE, LENGTH, LOCATION } \
' \
| (sed --unbuffered 1q; sort --key=2 --field-separator="$(printf '\t')" --reverse) \
| tee "$HOME/$PROJECT-curl-links.csv" \
| awk -v BINMODE=2 ' \
	BEGIN { FS=OFS="\t" } \
	$2 !~ /^200/ { print $1, $2 } \
' \
| sort --key=1 --field-separator="$(printf '\t')" \
> "$HOME/.$PROJECT-curl-links-error.csv" \
&& tput bel
```

#### Resulting files:
- _[PROJECT-NAME]-curl-log.txt_ - curl log for debugging purposes.
- _[PROJECT-NAME]-curl-links.csv_ - list of all the links with HTTP codes and some other information.
- _.[PROJECT-NAME]-curl-links-error.csv_ - used at step 3.





## Step 3
Replace `[PROJECT-NAME]` with the same project name as above, and run:

```Shell
PROJECT="[PROJECT-NAME]"; \
awk -v BINMODE=2 ' \
	BEGIN	{ FS=OFS="\t"; print "BROKEN LINK", "REFERER" } \
	NR==FNR	{ c[$1]++; next }; $1 in c { print $1, $2 } \
' "$HOME/.$PROJECT-curl-links-error.csv" "$HOME/.$PROJECT-wget-links-and-refs.csv" \
| cat \
	<(printf "%s\n" "S U M M A R Y") \
	"$HOME/.$PROJECT-curl-links-error.csv" \
	<(printf "\n%s\n" "D E T A I L S") \
	- \
	> "$HOME/$PROJECT-broken-links-$(date +'%d-%m-%Y').csv"
```

#### Resulting file:
- _[PROJECT-NAME]-broken-links-DD-MM-YYY.csv_ - list of the links with erroneous HTTP codes and "linked from" URLs (see the picture above).
