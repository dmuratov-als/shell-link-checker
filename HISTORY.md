## Version history
#### v.2.6.0 (20250705)
- New: failed requests during Wget spidering are now reported in $file_wget_errors
- Fixed: leading and trailing spaces, and all tabs in TITLE, etc. are now properly preserved by quoting the string in ${project}-curl-summary.tsv
- Fixed: double quotes in TITLE, etc. are now properly escaped in ${project}-curl-summary.tsv
- The resulting file list now includes "B" for bytes
- Removing duplicates is now performed with awk (which is memory-consuming in the case of hundreds of thousands of URLs, but saves on disk I/O operations)
- Removed saving duplicates to $file_wget_sitemap (due to both HEAD and GET requests being made)
- Regular expressions and range matches in gawk are tighter
- The superfluous decimal part in the "queued" number has been fixed.
- Variables, open files and commands are now reset or closed in awk when they are no longer needed
  
#### v.2.5.0 (20250123)
- Backward incompatibility: the file names are changed
- Added a check for minimum zsh version and availability of zsh modules
- Broader detection of custom URL schemes, the tel and callto schemes are no longer singled out, nor are the tel links included in the broken links report
- Fixed a bug when a wrong URL scheme was interpreted as the userinfo URL subcomponent (as "email:someone@domain.tld" instead of "mailto:someone@domain.tld")
- Fixed a bug when the start-of-string regex anchor was not correctly applied to the entire $subtree_only array
- Fixed a bug when exiting a script would close the current interactive shell
- Fixed a bug when empty URL list file triggered creation of the $address_file variable
- Added the "not supported" message for mailbox lists
- No attempt is made to read the manifest and browserconfig.xml files if they are missing
- Error messages when parsing the manifest and browserconfig.xml files are redirected to /dev/null
- Error messages for $file_wget_sitemap_tree are redirected to /dev/null
- Fixed the incorrect "Wget completed" message attribution for the "notify-send" command in the script 2
- Naming and messages/dialogs phrasing are more semantic, consistent, and clear
- Multiple code changes and improvements

#### v.2.4.2 (20240709)
- The sitemap tree is now generated by gawk (instead of by the tree utility).
  
#### v.2.4.1 (20240512)
- Added $XDG_RUNTIME_DIR to the list of temporary files locations.
- Fixed a race condition where the log content was displayed when Wget soft-failed (instead of only when hard-failed).
- Fixed a bug when URLs from an URLs list file were not added to the Wget result files other than ${project}-wget-links-and-refs.tsv.

#### v.2.4.0 (20240412):
- Added reading URLs from a file
- Added sitemap tree generation
- Shell alert on script completion changed to the system notification (Linux, MacOS)
- Date of the $file_broken_links file is taken at the end of the process, not at the beginning (useful if checking takes a day or a week)
- If the $subtree_only option is enabled, only relevant links are displayed
- The $subtree_only option now works correctly with URLs with or without trailing slashes.
- Improved error reporting
- Custom options do not overwrite the required ones
- Additional checks that all required files are present
- Single quotes in TITLE/og:title/description/og:description are unescaped
- Removed dummy curl --user foo:bar option
- Fixed "fatal error: out of heap memory" when counting the number of links using shell substitutions
- Fixed sorting of curl result files
- Fixed usage of --level Wget option and moved it to custom options block
- Fixed a bug when "NO TITLE" was reported due to curl's non-"HTTP error" problem
- Fixed a bug when the compressed log file was not overwritten
- Some speedup improvements with "mapfile" instead of input redirection
- Removed external dependencies mkdir, rm, mv in favor of the built-in ones
- Code modifications

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
