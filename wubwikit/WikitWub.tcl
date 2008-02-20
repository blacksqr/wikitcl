package require Mk4tcl
package require Wikit::Db
package require Wikit::Search
package require File
package require Mason
package require Convert
package require Direct
package require Html
package require fileutil
package require Form

package require Debug
package require Url
package require Query
package require Form
package require struct::queue
package require Http
package require Cookies
package require Session
package require WikitRss
package require Sitemap
package require stx
package require Responder
package require Honeypot

package provide WikitWub 1.0

Honeypot init dir [file join $::config(docroot) captcha]

proc pest {req} {return 0}	;# default [pest] catcher
catch {source [file join [file dirname [info script]] pest.tcl]}

# ::Wikit::GetPage {id} -
# ::Wikit::Expand_HTML {text}
# ::Wikit::pagevars {id args} - assign values to named vars

# ::Wikit::SavePage $id $C $host $name

# LookupPage {name} - find/create a page named $name in db, return its id
# InfoProc {db name} - lookup $name in db,
# returns a list: /$id (with suffix of @ if the page is new), $name, modification $date

namespace eval WikitWub {
    variable readonly ""

    # sortable - include javascripts and CSS for sortable table.
    proc sortable {r} {
	foreach js {common css standardista-table-sorting} {
	    dict lappend r -headers [<script> src /$js.js]
	}
	dict lappend r -headers [<style> media all "@import url(/sorttable.css);"]
	return $r
    }

    proc <P> {args} {
	puts stderr "<P> $args"
	return [<p> {*}$args]
    }

    variable templates
    variable titles

    # record a page template
    proc template {name title template} {
	variable templates; set templates($name) $template
	variable titles; set titles($name) $title
    }

    # page - format up a page using templates
    proc sendPage {r {tname page} {http {NoCache Ok}}} {
	variable templates
	variable titles
	if {$titles($tname) ne ""} {
	    dict lappend r -headers [<title> [uplevel 1 subst [list $titles($tname)]]]
	}
	dict set r -content [uplevel 1 subst [list $templates($tname)]]
	dict set r content-type x-text/wiki

	# run http filters
	foreach pf $http {
	    set r [Http $pf $r]
	}
	return $r
    }

    # Page sent when Wiki is in Read-Only Mode
    template ro {Wiki is currently Read-Only} {
	[<h1> "The Wiki is currently in Maintenance Mode"]
	[<p> "No new edits can be accepted at the moment."]
	[<p> "Reason: $readonly"]
	[<p> [<a> href /$N "Return to the page you were reading."]]
    }

    # standard page decoration
    template page {$name} {
	[div container {
	    [div header {
		[div logo [<a> href / class logo wiki.tcl.tk]]
		[<div> id title class title [tclarmour $Title]]
		[<div> id updated class updated $updated]
	    }]
	    [expr {[info exists ro]?$ro:""}]
	    [divID wrapper {
		[divID content {[tclarmour $C]}]
	    }]
	    [divID menu_area {
		[divID wiki_menu {[menuUL $menu]}]
		[expr {[info exists gsearch]?[gsearchF $query]:[searchF]}]
		[div navigation {
		    [divID page_toc $T]
		}]
		[div extra {
		    [divID wiki_toc $TOC]
		}]
	    }]
	    [div footer {
		[<p> id footer [variable bullet; join $footer $bullet]]
	    }]
	}]
    }

    # page sent when constructing a reference page
    template refs {References to $N} {
	[div container {
	    [div header {[<h1> "References to [Ref $N]"]}]
	    [div {wrapper content} {[tclarmour $C]}]
	    [<hr> noshade]
	    [div footer {
		[<p> id footer [variable bullet; join $footer $bullet]]
		[searchF]
	    }]
	}]
    }

    # page sent when constructing a transcluded reference page
    template refs_tc {References to $N} {
	[tclarmour $C]
    }

    # page sent when constructing a transcluded reference page
    template preview_tc {Preview of $N} {
	[tclarmour $C]
    }

    # page sent when editing a page
    template edit {Editing $N} {
	[div edit {
	    [div header {
		[div logo wiki.tcl.tk]
		[div title "Edit [tclarmour [Ref $N]]"]
		[div updated "make your changes then press Save below"]
	    }]
	    [div editcontents {
		[set disabled [expr {$nick eq ""}]
		 <form> edit method post action /_edit/save/$N {
		     [<textarea> C id editarea rows 30 cols 72 style width:100% [tclarmour $C]]
		     [<hidden> O [list [tclarmour $date] [tclarmour $who]]]
		     [<hidden> _charset_ {}]
		     [<submit> save class positive disabled $disabled value 1 {Save your changes}]
		     [<submit> cancel class button disabled 0 value 1 Cancel]
		     <button type='button' id='previewbutton' onclick='previewPage($N);'>Preview</button>
		     <button type='button' id='helpbutton' onclick='editHelp();'>Help</button>
		 }]
		[<blockquote> id helptext [subst {
                    [<hr>]
		    [<br>]
		    [<b> "Editing quick-reference:"] <button type='button' id='hidehelpbutton' onclick='hideEditHelp();'>Hide Help</button>
		    [<br>]
		    [<b> LINK] to [<b> "\[[<a> href ../6 target _blank {Wiki formatting rules}]\]"] - or to [<b> [<a> href http://here.com/ target _blank "http://here.com/"]] - use [<b> "\[http://here.com/\]"] to show as [<b> "\[[<a> href http://here.com/ target _blank 1]\]"]
		    [<br>]
		    [<b> BULLETS] are lines with 3 spaces, an asterisk, a space - the item must be one (wrapped) line
		    [<br>]
		    [<b> "NUMBERED LISTS"] are lines with 3 spaces, a one, a dot, a space - the item must be one (wrapped) line
		    [<br>]
		    [<b> PARAGRAPHS] are split with empty lines,
		    [<br>]
		    [<b> "UNFORMATTED TEXT"] starts with white space or is enclosed in lines containing <tt>======</tt>
		    [<br>]
		    [<b> HIGHLIGHTS] are indicated by groups of single quotes - use two for [<b> {''}] [<i> italics] [<b> {''}], three for [<b> '''bold''']. Back-quotes can be used for [<b> {`}]<tt>tele-type</tt>[<b> {`}].
		    [<br>]
		    [<b> SECTIONS] can be separated with a horizontal line - insert a line containing just 4 dashes
		    [<br>]
		    [<b> HEADERS] can be specified with lines containing **Header level 1**, ***Header level 2*** or ****Header level 3****
		}]]
		[<div> id previewarea_pre ""]
		[<div> class previewarea id previewarea ""]
		[<hr>]
		[If {$date != 0} {
		    [<i> "Last saved on [<b> [clock format $date -gmt 1 -format {%Y-%m-%d %T}]]"]
		}]
		[If {$who_nick ne ""} {
		    [<i> "by [<b> $who_nick]"]
		}]
		[If {$nick ne ""} {
		    (you are: [<b> $nick])
		}]
	    }]
	}]
    }

    # page sent to enable login
    template login {login} {
	[<p> "You must have a nickname to post here"]
	[<form> login method post action /_edit/login {
	    [<fieldset> login title Login {
		[<text> nickname title "Nickname"]
		[<submit> save value login "Login"]
	    }]
	    [<hidden> R [armour $R]]
	}]
    }

    # page sent when a browser sent bad utf8
    template badutf {bad UTF-8} {
	[<h2> "Encoding error on page $N - [Ref $N $name]"]
	[<p> "[<b> "Your changes have NOT been saved"], because the content your browser sent contains bogus characters. At character number $point"]
	[<p> $E]
	[<p> [<i> "Please check your browser."]]
	[<hr> size 1]
	[<p> [<pre> [armour $C]]]
	[<hr> size 1]
    }

    # page sent in response to a search
    template search {} {
	[<form> search method get action /_search {
	    [<fieldset> sfield title "Construct a new search" {
		[<legend> "Enter a Search Phrase"]
		[<text> S title "Append an asterisk (*) to search page contents" [tclarmour %S]]
		[<checkbox> SC title "search page contents" value 1; set _disabled ""]
		[<hidden> _charset_]
	    }]
	}]
	$C
    }

    # page sent when a save causes edit conflict
    template conflict {Edit Conflict on $N} {
	[<h2> "Edit conflict on page $N - [Ref $N $name]"]
	[<p> "[<b> "Your changes have NOT been saved"] because someone (at IP address $who) saved a change to this page while you were editing."]
	[<p> [<i> "Please restart a new [Ref /_edit/$N edit] and merge your version (which is shown in full below.)"]]
	[<p> "Got '$O' expected '$X'"]
	[<hr> size 1]
	[<p> [<pre> [armour $C]]]
	[<hr> size 1]
    }

    # record some session information per save
    proc setSession {page nick} {
	dict set r -session who $nick
	Session with r {
	    lappend edit [clock second] $page
	}
    }

    variable searchForm [string map {%S $search} [<form> search action /_search {
	[<fieldset> sfield title "Construct a new search" {
	    [<legend> "Enter a Search Phrase"]
	    [<text> S title "Append an asterisk (*) to search page contents" [tclarmour %S]]
	    [<checkbox> SC title "search page contents" value 1; set _disabled ""]
	    [<hidden> _charset_]
	}]
    }]]

    variable motd ""
    variable TOC ""
    variable TOCchange 0
    variable WELCOME ""
    variable WELCOMEchange 0

    proc div {ids content} {
	set divs ""
	foreach id $ids {
	    append divs "<div class='$id'>\n"
	}
	append divs [uplevel 1 subst [list $content]]
	append divs "\n"
	append divs [string repeat "\n</div>" [llength $ids]]
	return $divs
    }

    proc divID {ids content} {
	set divs ""
	foreach id $ids {
	    append divs "<div id='$id'>\n"
	}
	append divs [uplevel 1 subst [list $content]]
	append divs "\n"
	append divs [string repeat "\n</div>" [llength $ids]]
	return $divs
    }

    proc menuUL { l } {
	set m "<ul id='menu'>\n"
	foreach i $l {
	    #regsub {id='toggle_toc'} $i {id='toggle_toc_menu'} i
	    append m "<li>$i</li>"
	}
	append m "</ul>"
    }

    # return a search form
    proc searchF {} {
	return {<form id='searchform' action='/_search' method='get'>
	    <input type='hidden' name='_charset_'>
	    <input id='searchtxt' name='S' type='text' value='Search in titles' 
		onfocus='clearSearch();' onblur='setSearch();'>
	    </form>
	    <form id='gsearchform' action='/_gsearch' method='get'>
	    <input type='hidden' name='_charset_'>
	    <input id='googletxt' name='S' type='text' value='Search in pages' 
		onfocus='clearGoogle();' onblur='setGoogle();'>
	    </form>
	}
    }

    proc gsearchF {Q} {
	return "<form id='searchform' action='/_search' method='get'>
	    <input type='hidden' name='_charset_'>
	    <input id='searchtxt' name='S' type='text' value='Search in titles' 
		onfocus='clearSearch();' onblur='setSearch();'>
	    </form>
            <form id='gsearchform' action='' method='get' onSubmit='return googleQuery();'>
	    <input id='googletxt' type='text' value='$Q' 
		onfocus='clearGoogle();' onblur='setGoogle();'>
	    </form>
	"
    }

    variable maxAge "next month"	;# maximum age of login cookie
    variable cookie "wikit_e"		;# name of login cookie
    variable oldcookie "wikit"		;# name of login cookie

    #variable htmlhead {<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN">}
    variable htmlhead {<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN" "http://www.w3.org/TR/html4/loose.dtd">}
    variable language "en"	;# language for HTML

    # header sent with each page
    #<meta name='robots' content='index,nofollow' />
    variable head [subst {
	[<style> media all "@import url(/wikit.css);"]

	[<link> rel alternate type "application/rss+xml" title RSS href /rss.xml]
	<!--\[if lte IE 6\]>
		[<style> media all "@import 'ie6.css';"]
	<!\[endif\]-->
	<!--\[if gte IE 7\]>
		[<style> media all "@import 'ie7.css';"]
	<!\[endif\]-->
	[<script> {
	    function init() {
		// quit if this function has already been called
		if (arguments.callee.done) return;

		// flag this function so we don't do the same thing twice
		arguments.callee.done = true;

		try {
		    checkTOC();
		} catch (err) {
		    /* nothing */
		}
	    };

	    /* for Mozilla */
	    if (document.addEventListener) {
		document.addEventListener("DOMContentLoaded", init, false);
	    }

	    /* for Internet Explorer */
	    /*@cc_on @*/
	    /*@if (@_win32)
	    document.write("<script defer src=ie_onload.js><\/script>");
	    /*@end @*/
	    
	    /* for other browsers */
	    window.onload = init;
	}]
    }]

    # protected pages
    variable protected
    array set protected {Search 2 Changes 4 HoneyPot 5 Something 7 TOC 8 Init 9}
    foreach {n v} [array get protected] {
	set protected($v) $n
    }

    # html suffix to be sent on every page
    variable htmlsuffix [Honeypot link /$protected(HoneyPot).html]
    append htmlsuffix [<script> src /search.js] \n
    append htmlsuffix [<script> src /backrefs.js] \n
    append htmlsuffix [<script> src /_toc/toc.js] \n

    # convertor from wiki to html
    proc .x-text/wiki.text/html {rsp} {
	set rspcontent [dict get $rsp -content]

	if {[string match "<!DOCTYPE*" $rspcontent]} {
	    # the content is already fully HTML
	    set content $rspcontent
	} else {
	    variable htmlhead
	    set content "${htmlhead}\n"

	    variable language
	    append content "<html lang='$language'>" \n

	    append content <head> \n
	    if {[dict exists $rsp -headers]} {
		append content [join [dict get $rsp -headers] \n] \n
		dict unset rsp -headers
	    }

	    # add in some wikit-wide headers
	    variable head
	    variable protected
	    append content $head

	    append content </head> \n

	    append content <body> \n
	    append content $rspcontent
	    variable htmlsuffix; append content $htmlsuffix

	    if {[dict exists $rsp -postload]} {
		dict for {n v} [dict get $rsp -postload] {
		    append content $v \n
		}
	    }

	    append content </body> \n
	    append content </html> \n
	}

	return [dict replace $rsp \
		    -content $content \
		    -raw 1 \
		    content-type text/html]
    }

    proc /cclear {r args} {
	Cache clear
	return [Http Redir $r "http://[dict get $r host]/4"]
    }

    proc /cache {r args} {
	set C [Html dict2table [Cache::2dict] {-url -stale -hits -unmod -ifmod -when -size}]
	return [Http NoCache [Http Ok [sortable $r] $C x-text/wiki]]
    }

    proc /block {r args} {
	set C [Html dict2table [Block blockdict] {-site -when -why}]
	return [Http NoCache [Http Ok [sortable $r] $C x-text/wiki]]
    }

    # generate site map
    proc /sitemap {r args} {
	set p http://[Url host $r]/
	set map {}
	append map [Sitemap location $p "" mtime [file mtime $::config(docroot)/html/welcome.html] changefreq weekly] \n
	append map [Sitemap location $p 4 mtime [clock seconds] changefreq always priority 1.0] \n

	foreach i [mk::select wdb.pages -first 11 -min date 1 -sort date] {
	    append map [Sitemap location $p $i mtime [mk::get wdb.pages!$i date]] \n
	}

	return [Http NoCache [Http Ok $r [Sitemap sitemap $map] text/xml]]
    }

    proc /state {r} {
	set state [Activity state]
	set result [<table> summary {} class sortable [subst {
	    [<thead> [<tr> [<th> [join {cid socket thread backend ip start end log} </th><th>]]]]
	    [<tbody> [Foreach row $state {
		[<tr> [<td> [join $row </td><td>]]]
	    }]]
	}]]

	set r [sortable $r]	;# include the sortable js
	dict set r content-type x-text/wiki

	return [Http NoCache [Http Ok $r $result]]
    }

    proc /activity {r {L "current"} {F "html"} args} {
	# generate an activity page
	if {$L eq "log"} {
	    set act [Activity log]
	    set title "Activity Log"
	    set alt [<a> href "/_activity?L=current" "Current Activity"]
	} else {
	    set act [Activity current]
	    set title "Current Activity"
	    set alt [<a> href "/_activity?L=log" "Activity Log"]
	}

	switch -- $F {
	    csv {
		package require csv
		foreach a $act {
		    append result [::csv::joinlist $a] \n
		}
		dict set r content-type text/plain
	    }

	    html -
	    default {
		set table [<table> summary {} class sortable [subst {
		    [<thead> [<tr> [Foreach t [lindex $act 0] {
			[<th> [string totitle $t]]
		    }]]]
		    [<tbody> [Foreach a [lrange $act 1 end] {
			[<tr> class [If {[incr row] % 2} even else odd] \
			     [<td> [join $a </td>\n<td>]]]
		    }]]
		}]]
		set result "[<h1> $title]$table[<p> $alt]"

		set r [sortable $r]	;# include the sortable js
		dict set r content-type x-text/wiki
	    }
	}

	return [Http NoCache [Http Ok $r $result]]
    }

    proc list2plaintable {l columnclasses {tag ""}} {
	set row 0
	return [<table> class $tag summary {} [subst {
	    [<tbody> [Foreach vl $l {
		[<tr> class [If {[incr row] % 2} even else odd] \
		     [Foreach v $vl c $columnclasses {
			 [<td> class $c $v]
		     }]]
	    }]]
	}]]
    }

    # Special page: Recent Changes.
    variable delta [subst \u0394]
    variable delta [subst \u25B2]
    proc RecentChanges {} {
	variable delta
	set count 0
	set results {}
	set lastDay 0
	set threshold [expr {[clock seconds] - 7 * 86400}]
	set deletesAdded 0

	set result {}

	foreach id [mk::select wdb.pages -rsort date] {
	    lassign [mk::get wdb.pages!$id date name who page] date name who page

	    # these are fake pages, don't list them
	    if {$id == 2 || $id == 4} continue

	    # skip cleared pages
	    if {[string length $name] == 0
		|| [string length $page] <= 1} continue

	    # only report last change to a page on each day
	    set day [expr {$date/86400}]

	    #insert a header for each new date
	    incr count
	    if {$day != $lastDay} {

		if { [llength $result] } {
		    lappend results [list2plaintable $result {rc1 rc2 rc3} rctable]
		    set result {}

		    if { !$deletesAdded } {
			lappend results [<p> [<a> class cleared href /_cleared "Cleared pages (title and/or page)"]]
			set deletesAdded 1
		    }
		}

		# only cut off on day changes and if over 7 days reported
		if {$count > 100 && $date < $threshold} {
		    break
		}
		lappend results [<p> "[<b> [clock format $date -gmt 1 -format {%Y-%m-%d}]] [<span> class day [clock format $date -gmt 1 -format %A]]"]
		set lastDay $day
	    }

	    lappend result [list "[<a> href /$id [armour $name]] [<a> class delta href /_diff/$id#diff0 $delta]" $who [clock format $date -gmt 1 -format %T]]
	}

	if { [llength $result] } {
	    lappend results [list2plaintable $result {rc1 rc2 rc3} rctable]
	    if { !$deletesAdded } {
		lappend results [<p> [<a> href /_cleared "Cleared pages (title and/or page)"]]
	    }
	}

	if {$count > 100 && $date < $threshold} {
	    lappend results [<p> "Older entries omitted..."]
	}

	return [join $results \n]
    }

    proc /cleared { r } {
	set results ""
	set count 0
	set lastDay 0
	foreach id [mk::select wdb.pages -rsort date] {
	    lassign [mk::get wdb.pages!$id date name who page] date name who page

	    # these are fake pages, don't list them
	    if {$id == 2 || $id == 4} continue

	    # skip pages with contents in both name and page
	    if {[string length $name] && [string length $page] > 1} continue

	    # skip pages with date 0
	    if { $date == 0 } continue

	    set day [expr {$date/86400}]

	    if { $day != $lastDay } {
		if {$lastDay} {
		    lappend results </ul>
		}
		set lastDay $day
		lappend results [<p> [<b> [clock format $date -gmt 1 -format {%Y-%m-%d}]]]
		lappend results <ul>
	    }

	    if { [string length $name] } {
		set link [<a> href /$id $name]
	    } else {
		set link [<a> href /$id $id]
	    }
	    append link [<span> class dots ". . ."]
	    append link [<span> class nick $who]
	    append link [<span> class dots ". . ."]
	    append link [<span> class nick [clock format $date -gmt 1 -format %T]]
	    append link [<span> class dots ". . ."]
	    append link [<a> class delta href /_history/$id history]
	    lappend results [<li> $link]
	    incr count
	    if { $count >= 100 } {
		break
	    }
	}
	if {$lastDay} {
	    lappend results </ul>
	}

	set name "Cleared pages"
	set Title "Cleared pages"
	set T ""
	set N 0
	set updated ""
	variable menus
	foreach m {Home Recent Help} {
	    lappend menu $menus($m)
	}
	set footer $menu
	lappend footer $menus(Search)
	lappend footer $menus(TOC)

	set C [join $results "\n"]
	variable TOC
	return [sendPage $r]
    }

    proc get_page_with_version {N V A} {
	if {$A} {
	    set aC [::Wikit::AnnotatePageVersion $N $V]
	    set C ""
	    set prevVersion -1
	    foreach a $aC {
		lassign $a line lineVersion time who
		if { $lineVersion != $prevVersion } {
		    if { $prevVersion != -1 } {
			append C "\n<<<<<<"
		    }
		    append C "\n>>>>>>a;$N;$lineVersion;$who;" [clock format $time -format "%Y-%m-%d %T" -gmt true]
		    set prevVersion $lineVersion
		}
		append C "\n$line"
	    }
	    if { $prevVersion != -1 } {
		append C "\n<<<<<<"
	    }
	} elseif { $V >= 0 } {
	    set C [::Wikit::GetPageVersion $N $V]
	} else {
	    set C [GetPage $N]
	}
	return $C
    }

    proc wordlist { l } {
	set rl [split [string map {\  \0\  \n \ \n} $l] " "]
    }

    proc shiftNewline { s m } {
	if { [string index $s end] eq "\n" } {
	    return "$m[string range $s 0 end-1]$m\n"
	} else {
	    return "$m$s$m"
	}
    }

    proc unWhiteSpace { t } {
	set n {}
	foreach l $t {
	    # Replace all but leading white-space by single space
	    set tl [string trimleft $l]
	    set nl [string range $l 0 [expr {[string length $l] - [string length $tl] - 1 }]]
	    append nl [regsub -all {\s+} $tl " "]
	    lappend n $nl
	}
	return $n
    }

    proc /diff {r N {V -1} {D -1} {W 0} {T 0}} {
	Debug.wikit {/diff $N $V $D $W}

	set ext [file extension $N]	;# file extension?
	set N [file rootname $N]	;# it's a simple single page

	if {![string is integer -strict $N]
	    || ![string is integer -strict $V]
	    || ![string is integer -strict $D]
            || $N < 0
	    || $N >= [mk::view size wdb.pages]
	    || $ext ni {"" .txt .tk .str .code}
	} {
	    return [Http NotFound $r]
	}

	if {![string is integer -strict $T]} {
	    set T 0
	}

	set nver [expr {1 + [mk::view size wdb.pages!$N.changes]}]
	if { $V >= $nver || ($T == 0 && $D >= $nver) } {
	    return [Http NotFound $r]
	}

	if {$V < 0} {
	    set V [expr {$nver - 1}]	;# default
	}

	# If T is zero, D contains version to compare with
	# If T is non zero, D contains a number of days and /diff must
	# search for a version $D days older than version $V
	set updated ""
	if {$T == 0} {
	    if {$D < 0} {
		set D [expr {$nver - 2}]	;# default
	    }
	} else {
	    if {$V >= ($nver-1)} {
		set vt [mk::get wdb.pages!$N date]
	    } else {
		set vt [mk::get wdb.pages!$N.changes!$V date]
	    }
	    if {$D < 0} {
		set D 1
	    }
	    if {$V == ($nver - 1)} {
		if {$D==1} {
		    set updated "Changes in last day"
		} elseif {$D==7} {
		    set updated "Changes in last week"
		} else {
		    set updated "Changes in last $D days"
		}
	    }
	    set dt [expr {$vt-$D*86400}]
	    set dl [mk::select wdb.pages!$N.changes -max date $dt -rsort date]
	    if {[llength $dl]==0} {
		set dl [mk::select wdb.pages!$N.changes -sort date]
	    }
	    set D [lindex $dl 0]
	}

	Wikit::pagevars $N name

	set t1 [split [get_page_with_version $N $V 0] "\n"]
	if {!$W} { set uwt1 [unWhiteSpace $t1] } else { set uwt1 $t1 }
	set t2 [split [get_page_with_version $N $D 0] "\n"]
	if {!$W} { set uwt2 [unWhiteSpace $t2] } else { set uwt2 $t2 }
	set p1 0
	set p2 0
	set C ""
	foreach {l1 l2} [::struct::list::LlongestCommonSubsequence $uwt1 $uwt2] {
	    foreach i1 $l1 i2 $l2 {
		if { $W && $p1 < $i1 && $p2 < $i2 } {
		    set d1 ""
		    set d2 ""
		    set pd1 0
		    set pd2 0
		    while { $p1 < $i1 } {
			append d1 "[lindex $t1 $p1]\n"
			incr p1
		    }
		    while { $p2 < $i2 } {
			append d2 "[lindex $t2 $p2]\n"
			incr p2
		    }
		    set d1 [wordlist $d1]
		    set d2 [wordlist $d2]
		    foreach {ld1 ld2} [::struct::list::LlongestCommonSubsequence $d1 $d2] {
			foreach id1 $ld1 id2 $ld2 {
			    while { $pd1 < $id1 } {
				set w [lindex $d1 $pd1]
				if { [string length $w] } {
				    append C [shiftNewline $w "^^^^"]
				}
				incr pd1
			    }
			    while { $pd2 < $id2 } {
				set w [lindex $d2 $pd2]
				if { [string length $w] } {
				    append C [shiftNewline $w "~~~~"]
				}
				incr pd2
			    }
			    append C "[lindex $d1 $id1]"
			    incr pd1
			    incr pd2
			}
			while { $pd1 < [llength $d1] } {
			    set w [lindex $d1 $pd1]
			    if { [string length $w] } {
				append C [shiftNewline $w "^^^^"]
			    }
			    incr pd1
			}
			while { $pd2 < [llength $d2] } {
			    set w [lindex $d2 $pd2]
			    if { [string length $w] } {
				append C [shiftNewline $w "~~~~"]
			    }
			    incr pd2
			}
		    }
		} else {
		    while { $p1 < $i1 } {
			append C ">>>>>>n;$N;$V;;\n[lindex $t1 $p1]\n<<<<<<\n"
			incr p1
		    }
		    while { $p2 < $i2 } {
			append C ">>>>>>o;$N;$D;;\n[lindex $t2 $p2]\n<<<<<<\n"
			incr p2
		    }
		}
		if { [string equal [lindex $t1 $i1] [lindex $t2 $i2]] } {
		    append C "[lindex $t1 $i1]\n"
		} else {
		    append C ">>>>>>w;$N;$V;;\n[lindex $t1 $i1]\n<<<<<<\n"
		}
		incr p1
		incr p2
	    }
	}
	while { $p1 < [llength $t1] } {
	    append C ">>>>>>n;$N;$V;;\n[lindex $t1 $p1]\n<<<<<<\n"
	    incr p1
	}
	while { $p2 < [llength $t2] } {
	    append C ">>>>>>o;$N;$V;;\n[lindex $t2 $p2]\n<<<<<<\n"
	    incr p2
	}

	if { $W } {
	    set C [regsub -all "\0" $C " "]
	}

	if {$V >= 0} {
	    switch -- $ext {
		.txt {
		    return [Http NoCache [Http Ok $r $C text/plain]]
		}
		.tk {
		    set Title [<h1> [Ref $N]]
		    set name "Difference between version $V and $D for $name"
		    set C [::Wikit::TextToStream $C]
		    lassign [::Wikit::StreamToTk $C $N ::WikitWub::InfoProc] C U
		    append result "<p>$C"
		}
		.code {
		    set C [::Wikit::TextToStream $C]
		    set C [::Wikit::StreamToTcl $C ::WikitWub::InfoProc]
		    return [Http NoCache [Http Ok $r $C text/plain]]
		}
		.str {
		    set C [::Wikit::TextToStream $C]
		    return [Http NoCache [Http Ok $r $C text/plain]]
		}
		default {
		    set Title [Ref $N]
		    set name "Difference between version $V and $D for $name"
		    if { $W } {
			set C [::Wikit::ShowDiffs $C]
		    } else {
			lassign [::Wikit::StreamToHTML [::Wikit::TextToStream $C] / ::WikitWub::InfoProc] C U T BR
		    }
		    set tC "<span class='newwikiline'>Text added in version $V is highlighted like this</span>, <span class='oldwikiline'>text deleted from version $D is highlighted like this</span>"
		    if {!$W} { append tC ", <span class='whitespacediff'>text with only white-space differences is highlighted like this</span>" }
		    set C "$tC<hr>$C"
		}
	    }
	}

	set menu {}
	variable menus
	variable TOC
	if {![string length $updated]} {
	    set updated "Difference between version $V and $D"
	}
	foreach m {Home Recent Help} {
	    lappend menu $menus($m)
	}
	lappend menu [Ref /_history/$N History]
	lappend menu [Ref /_diff/$N "Last change"]
	lappend menu [Ref /_diff/$N?T=1&D=1 "Changes in last day"]
	lappend menu [Ref /_diff/$N?T=1&D=7 "Changes in last week"]
	set footer $menu
	lappend footer $menus(Search)
	lappend footer $menus(TOC)
	set T "" ;# Do not show page TOC, can be one of the diffs.
	return [sendPage $r]
    }

    proc /revision {r N {V -1} {A 0}} {
	Debug.wikit {/page $args}

	set ext [file extension $N]	;# file extension?
	set N [file rootname $N]	;# it's a simple single page

	if {![string is integer -strict $N]
	    || ![string is integer -strict $V]
	    || ![string is integer -strict $A]
            || $N < 0
	    || $N >= [mk::view size wdb.pages]
	    || $V < 0
	    || $ext ni {"" .txt .tk .str .code}
	} {
	    return [Http NotFound $r]
	}

	set nver [expr {1 + [mk::view size wdb.pages!$N.changes]}]
	if {$V >= $nver} {
	    return [Http NotFound $r]
	}

	variable menus
	set menu {}
	lappend menu [Ref /_history/$N History]
	foreach m {Home Recent Help} {
	    lappend menu $menus($m)
	}

	Wikit::pagevars $N name
	if {$V >= 0} {
	    switch -- $ext {
		.txt {
		    set C [get_page_with_version $N $V $A]
		    return [Http NoCache [Http Ok $r $C text/plain]]
		}
		.tk {
		    set Title "Version $V of [Ref $N]"
		    set name "Version $V of $name"
		    set C [::Wikit::TextToStream [get_page_with_version $N $V $A]]
		    lassign [::Wikit::StreamToTk $C $N ::WikitWub::InfoProc] C U T
		    append result "<p>$C"
		}
		.code {
		    set C [::Wikit::TextToStream [get_page_with_version $N $V $A]]
		    set C [::Wikit::StreamToTcl $C ::WikitWub::InfoProc]
		    return [Http NoCache [Http Ok $r $C text/plain]]
		}
		.str {
		    set C [::Wikit::TextToStream [get_page_with_version $N $V $A]]
		    return [Http NoCache [Http Ok $r $C text/plain]]
		}
		default {
		    if { [catch {get_page_with_version $N $V $A} C] } {
			return [Http NotFound $r]
		    } else {
			if {$A} {
			    set Title "Annotated version $V of [Ref $N]"
			    set name "Annotated version $V of $name"
			} else {
			    set Title "Version $V of [Ref $N]"
			    set name "Version $V of $name"
			}
			lassign [::Wikit::StreamToHTML [::Wikit::TextToStream $C] / ::WikitWub::InfoProc] C U T BR
			if { $V > 0 } {
			    lappend menu [Ref "/_revision/$N?V=[expr {$V-1}]&A=$A" "Previous version"]
			}
			if { $V < ($nver-1) } {
			    lappend menu [Ref "/_revision/$N?V=[expr {$V+1}]&A=$A" "Next version"]
			}
			if { $A } {
			    lappend menu [Ref "/_revision/$N?V=$V&A=0" "Not annotated"]
			} else {
			    lappend menu [Ref "/_revision/$N?V=$V&A=1" "Annotated"]
			}
		    }
		}
	    }
	    set footer $menu
	    lappend footer $menus(Search)
	    lappend footer $menus(TOC)
	}

	lappend menu [Ref /_history/$N History]
	set updated ""
	set T ""
	variable TOC
	return [sendPage $r]
    }

    # /history - revision history
    proc /history {r N {S 0} {L 25}} {
	Debug.wikit {/history $N $S $L}
	if {![string is integer -strict $N]
	    || ![string is integer -strict $S]
	    || ![string is integer -strict $L]
	    || $N >= [mk::view size wdb.pages]
	    || $S < 0
	    || $L <= 0} {
	    return [Http NotFound $r]
	}

	set name "Change history of [mk::get wdb.pages!$N name]"
	set Title "Change history of [Ref $N]"

	set menu {}
	variable menus
	foreach m {Home Recent Help} {
	    lappend menu $menus($m)
	}
	set C ""
#	set links ""
	set nver [expr {1 + [mk::view size wdb.pages!$N.changes]}]
	if {$S > 0} {
	    set pstart [expr {$S - $L}]
	    if {$pstart < 0} {
		set pstart 0
	    }
	    lappend menu [<a> href "$N?S=$pstart&L=$L" "Previous $L"]
#	    append links [<a> href "$N?S=$pstart&L=$L" "Previous $L"]
	}
	set nstart [expr {$S + $L}]
	if {$nstart < $nver} {
#	    if {$links ne {}} {
#		append links { - }
#	    }
	    lappend menu [<a> href "$N?S=$nstart&L=$L" "Next $L"]
#	    append links [<a> href "$N?S=$nstart&L=$L" "Next $L"]
	}
	set footer $menu
	lappend footer $menus(Search)
	lappend footer $menus(TOC)
#	if {$links ne {}} {
#	    append C <p> $links </p> \n
#	}
	if {[catch {Wikit::ListPageVersionsDB wdb $N $L $S} versions]} {
	    append C <pre> $versions </pre>
	} else {
	    Wikit::pagevars $N name
	    append C "<table summary='' class='history'><thead class='history'>\n<tr>"
	    foreach {column span} {Rev 1 Date 1 {Modified by} 1 {Line compare} 3 {Word compare} 3 Annotated 1 WikiText 1} {
		append C [<th> class [lindex $column 0] colspan $span $column]
	    }
	    append C "</tr></thead><tbody>\n"
	    set rowcnt 0
	    foreach row $versions {
		lassign $row vn date who
		set prev [expr {$vn-1}]
		set next [expr {$vn+1}]
		set curr [expr {$nver-1}]
		if { $rowcnt % 2 } {
		    append C "<tr class='odd'>"
		} else {
		    append C "<tr class='even'>"
		}
		append C [<td> class Rev [<a> href "/_revision/$N?V=$vn" rel nofollow $vn]]
		append C [<td> class Date [clock format $date -format "%Y-%m-%d %T" -gmt 1]]
		append C [<td> class Who $who]

		if { $prev >= 0 } {
		    append C [<td> class Line1 [<a> href "/_diff/$N?V=$vn&D=$prev#diff0" $prev]]
		} else {
		    append C <td></td>
		}
		if { $next < $nver } {
		    append C [<td> class Line2 [<a> href "/_diff/$N?V=$vn&D=$next#diff0" $next]]
		} else {
		    append C <td></td>
		}
		if { $vn != $curr } {
		    append C [<td> class Line3 [<a> href "/_diff/$N?V=$curr&D=$vn#diff0" Current]]
		} else {
		    append C <td></td>
		}

		if { $prev >= 0 } {
		    append C [<td> class Word1 [<a> href "/_diff/$N?V=$vn&D=$prev&W=1#diff0" $prev]]
		} else {
		    append C <td></td>
		}
		if { $next < $nver } {
		    append C [<td> class Word2 [<a> href "/_diff/$N?V=$vn&D=$next&W=1#diff0" $next]]
		} else {
		    append C <td></td>
		}
		if { $vn != $curr } {
		    append C [<td> class Word3 [<a> href "/_diff/$N?V=$curr&D=$vn&W=1#diff0" Current]]
		} else {
		    append C <td></td>
		}

		append C [<td> class Annotated [<a> href "/_revision/$N?V=$vn&A=1" $vn]]
		append C [<td> class WikiText [<a> href "/_revision/$N.txt?V=$vn" $vn]]
		append C </tr> \n
		incr rowcnt
	    }
	    append C </tbody></table> \n
	}
#	if {$links ne {}} {
#	    append C <p> $links </p> \n
#	}

	set updated ""
	set T ""
	variable TOC
	return [sendPage $r]
    }

    # Ref - utility proc to generate an <A> from a page id
    proc Ref {url {name "" } args} {
	if {$name eq ""} {
	    set page [lindex [file split $url] end]
	    if {[catch {
		set name [mk::get wdb.pages!$page name]
	    }]} {
		set name $page
	    }
	}
	return [<a> href /[string trimleft $url /] {*}$args [armour $name]]
    }

    variable menus
    variable bullet " &bull; "

    # Init common menu items
    set menus(Home)             [<a> href "/" Home]
    set menus(Recent) [Ref 4 "Recent changes"]
    set menus(Help)             [Ref 3 "Help"]
    set menus(Search)           [Ref 2 "Search"]
    set menus(TOC)		[<a> href "/_toc/toggle" "Toggle Menu"]

    set redir {meta: http-equiv='refresh' content='10;url=$url'

	<h1>Redirecting to $url</h1>
	<p>$content</p>
    }

    proc redir {r url content} {
	variable redir
	return [Http NoCache [Http SeeOther $r $url [subst $redir]]]
    }

    proc /who {r} {
	set C [Html dict2table [dict get $r -session] {who edit}]
	return [Http NoCache [Http Ok [sortable $r] $C x-text/wiki]]
    }

    proc /login {r {nickname ""} {R ""}} {
	# cleanse nickname
	regsub -all {[^A-Za-z0-0_]} $nickname {} nickname

	if {$nickname eq ""} {
	    # this is a call to /login with no args,
	    # in order to generate the /login page
	    Debug.wikit {/login - redo with referer}
	    set R [Http Referer $r]
	    set r [movecookie $r]
	    return [sendPage $r login]]]
	}

	if {[dict exists $r -cookies]} {
	    set cdict [dict get $r -cookies]
	} else {
	    set cdict [dict create]
	}
	set dom [dict get $r -host]

	# include an optional expiry age
	variable maxAge
	if {![string is integer -strict $maxAge]} {
	    if {[catch {
		expr {[clock scan $maxAge] - [clock seconds]}
	    } maxAge]} {
		set age {}
	    } else {
		set age [list -max-age $maxAge]
	    }
	}

	if {$maxAge} {
	    #set age [list -max-age $maxAge]
	    set then [expr {$maxAge + [clock seconds]}]
	    set age [clock format $then -format "%a, %d-%b-%Y %H:%M:%S GMT" -gmt 1]
	    set age [list -expires $age]
	} else {
	    set age {}
	}

	variable cookie
	Debug.wikit {/login - created cookie $nickname with R $R}
	set cdict [Cookies add $cdict -path /_edit/ -name $cookie -value $nickname {*}$age]

	dict set r -cookies $cdict
	if {$R eq ""} {
	    set R [Http Referer $r]
	    if {$R eq ""} {
		set R "http://[dict get $r host]/"
	    }
	}

	return [redir $r $R [<a> href $R "Created Account"]]
    }

    # move old cookies from path / to path /_edit/
    proc movecookie {r} {
	variable oldcookie
	set cdict [dict get $r -cookies]

        set cl [Cookies match $cdict -name $oldcookie]
	if {[llength $cl] != 1} {
	    Debug.wikit {no old cookie}
	    return $r
	}

	set cdict [Cookies clear $cdict -name $oldcookie]
	dict set r cookies $cdict
	Debug.wikit {Cookie CLEAR}

	return $r
    }

    proc invalidate {r url} {
	Debug.wikit {invalidating $url} 3
	Cache delete http://[dict get $r host]/$url
    }

    proc locate {page {exact 1}} {
	Debug.wikit {locate '$page'}
	variable cnt

	# try exact match on page name
	if {[string is integer -strict $page]} {
	    Debug.wikit {locate - is integer $page}
	    return $page
	}

	set N [mk::select wdb.pages name $page -min date 1]
	switch [llength $N] {
	    1 {
		# uniquely identified, done
		Debug.wikit {locate - unique by name - $N}
		return $N
	    }

	    0 {
		# no match on page name,
		# do a glob search over names,
		# where AbCdEf -> *[Aa]b[Cc]d[Ee]f*
		# skip this if the search has brackets (WHY?)
		if {[string first {[} $page] < 0} {
		    regsub -all {[A-Z]} $page "\\\[&\[string tolower &\]\\\]" temp
		    set temp "*[subst -novariable $temp]*"
		    set N [mk::select wdb.pages -glob name $temp -min date 1]
		}
		if {[llength $N] == 1} {
		    # glob search was unambiguous
		    Debug.wikit {locate - unique by title search - $N}
		    return $N
		}
	    }
	}

	# ambiguous match or no match - make it a keyword search
	set ::Wikit::searchLong [regexp {^(.*)\*$} $page x ::Wikit::searchKey]
	Debug.wikit {locate - kw search}
	return 2	;# the search page

	# these two globals (searchKey and searchLong) control the
	# representation of page 2 - they will cause it to return
	# a list of matches
    }

    proc /search {r {S ""} args} {
	if {$S eq "" && [llength $args] > 0} {
	    set S [lindex $args 0]
	}

	Debug.wikit {/search: '$S'}
	dict set r -prefix "/$S"
	dict set r -suffix $S

	set ::Wikit::searchLong [regexp {^(.*)\*$} $S x ::Wikit::searchKey]
	return [WikitWub do $r 2]
    }

    proc /gsearch {r {S ""}} {
	set name "Search"
	set Title "Search"
	set updated "powered by <img class='branding' src='http://www.google.com/uds/css/small-logo.png'</img>"
	set C [<script> src "http://www.google.com/jsapi?key=ABQIAAAAd_WRwEznyjHoNeYTARvZfhRBhBrTIb6FwgkxOANVg_BWVEsofRRgZuiTm8-2tzH-sy6S3NIdSJANqw"]
	append C \n
	append C [<script> {google.load('search', '1');}]
	append C \n
	set menu {}
	variable menus
	variable TOC
	variable gsearch 1
	variable query $S
	foreach m {Home Recent Help} {
	    lappend menu $menus($m)
	}
	set footer $menu
	set T ""
	set r [sendPage $r]
	unset gsearch
	return $r
    }

    proc who {r} {
	variable cookie
	set cdict [dict get $r -cookies]
	set cl [Cookies match $cdict -name $cookie]
	if {[llength $cl] != 1} {
	    return ""
	} else {
	    Debug.wikit {who /edit/ $cl}
	    return [dict get [Cookies fetch $cdict -name $cookie] -value]
	}
    }

    proc /preview { r N O } {
	puts "N=$N, O=$O"
	set C [::Wikit::TextToStream $O]
	lassign [::Wikit::StreamToHTML $C / ::WikitWub::InfoProc] C U T BR
	return [sendPage $r preview_tc]
    }

    proc /save {r N C O save cancel preview } {

	puts "save=$save, cancel=$cancel, preview=$preview"

	if { ([string tolower $cancel] eq "cancel") || ([string is integer -strict $cancel] && $cancel) } {
	    set url http://[Url host $r]/$N
	    return [redir $r $url [<a> href $url "Canceled page edit"]]
	}

	variable readonly
	if {$readonly ne ""} {
	    return [sendPage $r ro]
	}

	if {![string is integer -strict $N]} {
	    return [Http NotFound $r]
	}
	if {$N >= [mk::view size wdb.pages]} {
	    return [Http NotFound $r]
	}

	if {[catch {
	    ::Wikit::pagevars $N name date who
	} er eo]} {
	    return [Http NotFound $er [subst {
		[<h2> "$N is not a valid page."]
		[<p> "[armour $r]([armour $eo])"]
	    }]]
	}

	# is the caller logged in?
	set nick [who $r]
	set when [expr {[dict get $r -received] / 1000000}]

	# temporary fix - move cookies under -path /_edit/
        set r [movecookie $r]

	Debug.wikit {/edit/save N:$N [expr {$C ne ""}] who:$nick when:$when - modified:"$date $who" O:$O }

	# if there is new page content, save it now
	variable protected
	if {$N ne ""
	    && $C ne ""
	    && ![info exists protected($N)]
	} {
	    # added 2002-06-13 - edit conflict detection
            if {$O ne [list $date $who]} {
		#lassign [split [lassign $O ewhen] @] enick eip
		if {$who eq "$nick@[dict get $r -ipaddr]"} {
		    # this is a ghostly conflict-with-self - log and ignore
		    Debug.wikit "Conflict on Edit of $N: '$O' ne '[list $date $who]' at date $when"
		    #set url http://[dict get $r host]/$N
		    #return [redir $r $url [<a> href $url "Edited Page"]]
		} else {
		    Debug.wikit {conflict $N}
		    set X [list $date $who]
		    return [sendPage $r conflict {NoCache Conflict}]
		}
	    }

	    # newline-normalize content
	    set C [string map {\r\n \n \r \n} $C]

	    # check the content for utf8 correctness
	    # this metadata is set by Query parse/cconvert
	    set point [Dict get? [Query metadata [dict get $r -Query] C] -bad]
	    if {$point ne ""
		&& $point < [string length $C] - 1
	    } {
		if {$point >= 0} {
		    incr point
		    binary scan [string index $C $point] H* bogus
		    set C [string replace $C $point $point "<BOGUS 0x$bogus>"]
		    set E [string range $C [expr {$point-50}] [expr {$point-1}]]
		} else {
		    set E ""
		}
		Debug.wikit {badutf $N}
		return [sendPage $r badutf]
	    }

	    # Only actually save the page if the user selected "save"
	    invalidate $r $N
	    invalidate $r 4
	    invalidate $r _ref/$N
	    invalidate $r rss.xml

	    # if this page did not exist before:
	    # remove all referencing pages.
	    #
	    # this makes sure that cache entries point to a filled-in page
	    # from now on, instead of a "[...]" link to a first-time edit page
	    if {$date == 0} {
		foreach from [mk::select wdb.refs to $N] {
		    invalidate $r [mk::get wdb.refs!$from from]
		}
	    }

	    set who $nick@[dict get $r -ipaddr]
	    Debug.wikit {SAVING $N}
	    if {[catch {
		if {[string match "*Cloverfield*" $name]} {
		    #set when [clock scan "1/1/71"]
		}
		::Wikit::SavePage $N [string map {"Robert Abitbol" unperson RobertAbitbol unperson Abitbol unperson} $C] $who $name $when
	    } err eo]} {
		set readonly $err
	    }
	}

	Debug.wikit {save done $N}
	set url http://[Url host $r]/$N
	return [redir $r $url [<a> href $url "Edited Page"]]
    }

    proc GetPage {id} {
	return [mk::get wdb.pages!$id page]
    }

    # /reload - direct url to reload numbered pages from fs
    proc /reload {r} {
	foreach {} {}
    }
	    
    # called to generate an edit page
    proc /edit {r N args} {
	variable readonly
	variable protected
	if {$readonly ne ""} {
	    return [sendPage $r ro]
	}

	if {![string is integer -strict $N]} {
	    return [Http NotFound $r]
	}
	if {[info exists protected($N)]} {
	    return [Http Forbidden $r]
	}
	if {$N >= [mk::view size wdb.pages]} {
	    return [Http NotFound $r]
	}

	# is the caller logged in?
	set nick [who $r]
	
	if {$nick eq ""} {
	    set R ""	;# make it return here
	    # TODO KBK: Perhaps allow anon edits with a CAPTCHA?
	    # Or at least give a link to the page that gets the cookie back.
	    return [sendPage $r login]
	}

	::Wikit::pagevars $N name date who	;# get the last change author

	set who_nick ""
	regexp {^(.+)[,@]} $who - who_nick
	set C [armour [GetPage $N]]
	if {$C eq ""} {
	    set C "This is an empty page.\n\nEnter page contents here or click cancel to leave it empty.\n\n----\n!!!!!!\n%| enter categories here |%\n!!!!!!\n"
	}

	setSession $N $nick	;# set some session data

	return [sendPage $r edit]
    }

    proc /motd {r} {
	variable motd

	puts "\n\n\n\n\nmotd: [file join $::config(docroot) motd]\n\n\n\n\n"

	catch {set motd [::fileutil::cat [file join $::config(docroot) motd]]}
	set motd [string trim $motd]

	invalidate $r 4	;# make the new motd show up

	set R [Http Referer $r]
	if {$R eq ""} {
	    set R http://[dict get $r host]/4
	}
	return [redir $r $R [<a> href $R "Loaded MOTD"]]
    }

    proc /reloadTOC {r} {
	variable TOCchange 

	set tocf [file join $::config(docroot) TOC]

	set changed [file mtime $tocf]
	if {$changed <= $TOCchange} {
	    set R http://[dict get $r host]/4
	    return [redir $r $R [<a> href $R "No Change"]]
	}

	set TOCchange $changed

	variable TOC
	variable IMTOC
	catch {set TOC [::fileutil::cat $tocf]}
	set TOC [string trim $TOC]
	unset -nocomplain IMTOC
	if { [string length $TOC] } {
	    lassign [::Wikit::FormatWikiToc $TOC] TOC IMTOCl
	    array set IMTOC $IMTOCl
	}

	set R http://[dict get $r host]/4
	return [redir $r $R [<a> href $R "Loaded MOTD"]]
    }

    proc /reloadWELCOME {r} {
	variable WELCOMEchange

	set wf [file join $::config(docroot) html welcome.html]

	set changed [file mtime $wf]
	if {$changed <= $WELCOMEchange} {
	    set R http://[dict get $r host]/4
	    return [redir $r $R [<a> href $R "No Change"]]
	}
	
	set WELCOMEchange $changed

	variable WELCOME
	catch {set WELCOME [::fileutil::cat $wf]}
	set WELCOME [string trim $WELCOME]

	set R http://[dict get $r host]/4
	return [redir $r $R [<a> href $R "Loaded MOTD"]]
    }

    proc /reloadCSS {r} {
	invalidate $r wikit.css
	invalidate $r ie6.css
	set R [dict get $r -url]
	Cache delete http://[dict get $r host]/_toc
	return [Http Ok $r [<a> href $R "Loaded CSS"] text/html]
    }

    proc /welcome { r} {
	variable TOC
	variable WELCOME
	variable protected
	variable menus

	set menu {}
	lappend menu $menus(Recent)
	lappend menu $menus(Help)
	set footer $menu
	lappend footer $menus(Search)
	lappend footer $menus(TOC)

	set Title "Welcome to the Tclers Wiki!"
	set updated ""
	set ro ""
	set C $WELCOME
	set T ""
	set name "Welcome to the Tclers Wiki!"

	return [sendPage $r]
    }

    # list2table - convert list into sortable HTML table
    proc list2table {l header {footer {}}} {
	set row 0
	return [<table> class sortable summary {} [subst {
	    [<thead> [<tr> [Foreach t $header {
		[<th> class $t  [string totitle $t]]
	    }]]]
	    [If {$footer ne {}} {
		[<tfoot> [<tr> [Foreach t $footer {[<th> $t]}]]]
	    }]
	    [<tbody> [Foreach vl $l {
		[<tr> class [If {[incr row] % 2} even else odd] \
		     [Foreach th $header v $vl {
			 [<td> class $th $v]
		     }]]
	    }]]
	}]]
    }

    # called to generate a page with references
    proc /ref {r N A} {
	if { ![string is integer -strict $A] } {
	    set A 0
	}
	#set N [dict get $r -suffix]
	Debug.wikit {/ref $N}
	if {![string is integer -strict $N]} {
	    return [Http NotFound $r]
	}
	if {$N >= [mk::view size wdb.pages]} {
	    return [Http NotFound $r]
	}

	set refList ""
	foreach from [mk::select wdb.refs to $N] {
	    set from [mk::get wdb.refs!$from from]
	    ::Wikit::pagevars $from name who date
	    lappend refList [list [::Wikit::GetTimeStamp $date] $name $who $from]
	}
	set refList [lsort -dictionary -index 1 $refList]
	set tableList {}
	foreach ref $refList {
	    lassign $ref date name who from
	    lappend tableList [list $date [Ref $from {}] $who]
	}

	if { $A } { 
	    set C "<ul class='backrefs'>\n"
	    foreach br $tableList {
		lassign $br date ref who
		append C "[<li> $ref]\n"
	    }
	    append C "</ul>\n"
	} else {
	    set C [list2table $tableList {Date Name Who} {}]
	    # include javascripts and CSS for sortable table.
	    set r [sortable $r]
	} 
	variable menus
	set menu {}
	foreach m {Home Recent Help} {
	    lappend menu $menus($m)
	}
	set footer $menu
	lappend footer $menus(Search)
	lappend footer $menus(TOC)

	set name "References to $N"
	set Title "References to [Ref $N]"
	set updated ""
	set T ""
	set tplt page
	if { $A } {
	    set tplt refs_tc
	}
	variable TOC
	return [sendPage $r $tplt]
    }

    proc InfoProc {ref} {
	set id [::Wikit::LookupPage $ref wdb]
	::Wikit::pagevars $id date name

	if {$date == 0} {
	    set id _edit/$id ;# enter edit mode for missing links
	} else {
	    set id /$id	;# add a leading / which format.tcl will strip
	}

	return [list /$id $name $date]
    }

    proc search {key date} {
	Debug.wikit {search: '$key'}
	set long [regexp {^(.*)\*+$} $key x key]

	set fields name
	if {$long} {
	    lappend fields page
	}

	set search {}
	foreach k [split $key " "] {
	    if {$k ne ""} {
		lappend search -keyword $fields [string map {+ " "} $k]
	    }
	}
	if { $date == 0 } {
	    set rows [mk::select wdb.pages -rsort date {*}$search]
	} else {
	    set rows [mk::select wdb.pages -max date $date -rsort date {*}$search]
	}

	# tclLog "SearchResults key <$key> long <$searchLong>"
	set rdate $date
	set count 0
	set result "Searched for \"'''$key'''\" (in page titles"
	if {$long} {
	    append result { and contents}
	}
	append result "):\n\n"
	set pcnt 0
	foreach i $rows {
	    # these are fake pages, don't list them
	    if {$i == 2 || $i == 4 || $i == 5} continue

	    ::Wikit::pagevars $i date name
	    if {$date == 0} continue	;# don't list empty pages

	    # ignore "near-empty" pages with at most 1 char, 30-09-2004
	    if {[mk::get wdb.pages!$i -size page] <= 1} continue

	    if { $count < 100 } { 
		append result "   * [::Wikit::GetTimeStamp $date] . . . \[$name\]\n"
		set rdate $date
		incr count
	    }

	    incr pcnt
	}

	if {$count == 0} {
	    append result "   * '''''No matches found'''''\n"
	    set rdate 0
	} else {
	    append result "   * ''Displayed $count matches''\n"
	    if {$pcnt > $count} {
		append result "   * ''Remaining [expr {$pcnt - $count + 1}] matches omitted...''\n"
	    } else {
		set rdate 0
	    }
	}

	return [list $result $rdate $long]
    }

    variable trailers {@ _edit ! _ref - _diff + _history}
    proc do {r term} {

	# decompose name
	set N [file rootname $term]	;# it's a simple single page
	set ext [file extension $term]	;# file extension?

	# strip fancy terminator shortcuts off end
	set fancy [string index $N end]
	if {$fancy in {@ ! - +}} {
	    set N [string range $N 0 end-1]
	} else {
	    set fancy ""
	}

	# handle searches
	if {![string is integer -strict $N]} {
	    set N [locate $term]
	    if {$N == "2"} {
		# locate has given up - can't find a page - go to search
		return [Http Redir $r "http://[dict get $r host]/_search" S [Query decode $term$fancy]]
	    } elseif {$N ne $term} {
		# we really should redirect
		return [Http Redir $r "http://[dict get $r host]/$N"]
	    }
	}

	# term is a simple integer - a page number
	if {$fancy ne ""} {
	    variable trailers
	    # we need to redirect to the appropriate spot
	    set url [dict get $trailers $fancy]/$N
	    return [Http Redir $r "http://[dict get $r host]/$url"]
	}

	set date [clock seconds]	;# default date is now
	set name ""	;# no default page name
	set who ""	;# no default editor
	set cacheit 1	;# default is to cache
	set T ""
	set BR {}

	switch -- $N {
	    2 {
		# search page
		set qd [Dict get? $r -Query]
		if {[Query exists $qd S]
		    && [set term [Query value $qd S]] ne ""
		} {
		    # search page with search term supplied
		    set search [armour $term]

		    # determine search date
		    if {[Query exists $qd F]} {
			set qdate [Query value $qd F]
			if {![string is integer -strict $qdate]} {
			    set qdate 0
			}
		    } else {
			set qdate 0
		    }

		    lassign [search $term $qdate] C nqdate long
		    set C [::Wikit::TextToStream $C]
		    lassign [::Wikit::StreamToHTML $C / ::WikitWub::InfoProc] C U T BR
		    if { $nqdate } {
			append C [<p> [<a> href "/_search?S=[armour $term]&F=$nqdate&_charset_=utf-8" "More search results..."]]
		    }
		    if { $long } {
			append C <p> 
			append C [<a> href "/_search?S=[armour [string trimright $term *]]&_charset_=utf-8" "Repeat search in titles only"]
			append C ", or remove trailing asterisks from the search string to search the titles only.</p>"
		    } else {
			append C <p> 
			append C [<a> href "/_search?S=[armour $term*]&_charset_=utf-8" "Repeat search in titles and contents"]
			append C ", or append an asterisk to the search string to search the page contents as well as titles.</p>"
		    }
		    set q [string trimright $term *]
		    append q " site:http://wiki.tcl.tk"
		    append C [<p> [<a>  target _blank href "http://www.google.com/search?q=[armour $q]" "Click here to see all matches on Google Web Search"]]
		} else {
		    # send a search page
		    set search ""
		    set C ""
		}

		variable searchForm; set C "[subst $searchForm]$C"

		set name "Search"
		set cacheit 0	;# don't cache searches
	    }

	    4 {
		# Recent Changes page
		variable motd
		set C "${motd}[RecentChanges]"
		set name "Recent Changes"
	    }

	    default {

		# simple page - non search term
		if {$N >= [mk::view size wdb.pages]} {
		    return [Http NotFound $r]
		}

		# set up a few standard URLs an strings
		if {[catch {::Wikit::pagevars $N name date who}]} {
		    return [Http NotFound $r]
		}

		# fetch page contents
		switch -- $ext {
		    .txt {
			set C [GetPage $N]
			return [Http NoCache [Http Ok $r $C text/plain]]
		    }
		    .tk {
			set C [::Wikit::TextToStream [GetPage $N]]
			lassign [::Wikit::StreamToTk $C $N ::WikitWub::InfoProc] C U T
			return [Http NoCache [Http Ok $r $C text/plain]]
		    }
		    .str {
			set C [::Wikit::TextToStream [GetPage $N]]
			return [Http NoCache [Http Ok $r $C text/plain]]
		    }
		    .code {
			set C [::Wikit::TextToStream [GetPage $N]]
			set C [::Wikit::StreamToTcl $C]
			return [Http NoCache [Http Ok $r $C text/plain]]
		    }
		    default {
			set C [::Wikit::TextToStream [GetPage $N]]
			lassign [::Wikit::StreamToHTML $C / ::WikitWub::InfoProc] C U T BR
			foreach {containerid bref} $BR {
			    if {[string length $bref]} {
				set brefpage [::Wikit::LookupPage $bref wdb]
			    } else {
				set brefpage $N
			    }
			    dict set r -postload backrefs [<script> "getBackRefs($brefpage,'$containerid')"]
			}
		    }
		}
	    }
	}
		
	Debug.wikit {located: $N}

	# set up backrefs
	set refs [mk::select wdb.refs to $N]
	Debug.wikit {[llength $refs] backrefs to $N}
        switch -- [llength $refs] {
	    0 {
		set backRef ""
		set Refs ""
		set Title [armour $name]
	    }
	    1 {
		set backRef /_ref/$N
		set Refs "[Ref $backRef Reference] - "
		set Title [Ref $backRef $name title "click to see reference to this page"]
	    }
	    default {
		set backRef /_ref/$N
		set Refs "[llength $refs] [Ref $backRef {References to this page}]"
		set Title [Ref $backRef $name title "click to see [llength $refs] references to this page"]
		Debug.wikit {backrefs: backRef:'$backRef' Refs:'$Refs' Title:'$Title'} 10
	    }
	}

	# arrange the page's tail
	set updated ""
	if {$N != 4} {
	    if {$date != 0} {
		set update [clock format $date -gmt 1 -format {%Y-%m-%d %T}]
		set updated "Updated $update"
	    }

	    if {$who ne "" &&
		[regexp {^(.+)[,@]} $who - who_nick]
		&& $who_nick ne ""
	    } {
		append updated " by $who_nick"
	    }
	    if {[string length $updated]} {
		variable delta
		append updated " " [<a> class delta href /_diff/$N#diff0 $delta]
	    }
	}
	set menu [list]

	variable protected
	variable menus
	foreach m {Home Recent Help} {
	    lappend menu $menus($m)
	}
	if {![info exists protected($N)]} {
	    if {!$::roflag} {
		lappend menu [Ref /_edit/$N Edit]
	    }
	    lappend menu [Ref /_history/$N History]
	    lappend menu [Ref $backRef References]
	}
	set footer $menu
	lappend footer $menus(Search)
	lappend footer $menus(TOC)

	#set Title "<h1 class='title'>$Title</h1>"
	if {0} {
	    # get the page title
	    if {![regsub {^<p>(<img src=".*?")>} $C [Ref 0 $backRef] C]} {
		set Title "<h1 class='title'>$Title</h1>"
	    } else {
		set Title ""
	    }
	}
	variable TOC
	variable readonly
	if {$readonly ne ""} {
	    set ro "<it>(Read Only Mode: $readonly)</it>"
	} else {
	    set ro ""
	}

	if {$cacheit} {
	    return [sendPage [Http CacheableContent $r $date] page DCache]
	} else {
	    return [sendPage $r]
	}
    }

    namespace export -clear *
    namespace ensemble create -subcommands {}
}

Convert init

# initialize wikit specific Direct domain and Convert domain
Direct init wikit namespace ::WikitWub prefix /_wub ctype "x-text/wiki"
Convert Namespace ::WikitWub

#### Sinorca package
# provides a page-level conversion
package require Sinorca
Sinorca init path /_sinorca/
Convert Namespace ::Sinorca

package require Dub
Dub init prefix /_dub/
Direct init dub namespace ::Dub prefix /_dub ctype "x-text/html-fragment"

#### jQ - jQuery framework
package require jQ
jQ init prefix /jquery

package require Commenter
Direct init doc namespace ::Commenter prefix /_doc ctype "x-text/html-fragment"

# directories of static files
foreach {dom expiry} {css {next week} images {next week} scripts {next week} img {next week} html 0 bin 0} {
    File $dom -root [file join $::config(docroot) $dom] -expires $expiry
}

if {[file exists /var/www/webalizer]} {
    Mason webalizer -root /var/www/webalizer -url /_stats/ -auth .before -wrapper .after -dirhead {name size mtime}
}

# Wub documentation directory
Mason wub -url /_wub -root [file join $::config(wubdir) docs] -auth .before -wrapper .after -dirhead {name size mtime}
Convert Namespace ::MConvert

# set message of the day (if any) to be displayed on /4
catch {
    set ::WikitWub::motd [::fileutil::cat [file join $::config(docroot) motd]]
}

# set table of contents (if any) to be displayed on in left column menu
catch {
    set ::WikitWub::TOC [::fileutil::cat [file join $::config(docroot) TOC]]
    unset -nocomplain ::WikitWub::IMTOC
    if { [string length $::WikitWub::TOC] } {
	lassign [::Wikit::FormatWikiToc $::WikitWub::TOC] ::WikitWub::TOC IMTOCl
	array set ::WikitWub::IMTOC $IMTOCl
    }
}

catch {
    set ::WikitWub::WELCOME [::fileutil::cat [file join $::config(docroot) html welcome.html]]
}

# Disconnected - courtesy indication that we've been disconnected
proc Disconnected {args} {
    # we're pretty well stateless
}

# Responder::post - postprocess response by converting
proc Responder::post {rsp} {
    return [::Convert do $rsp]
}

# Incoming - indication of incoming request
proc Incoming {req} {

    puts "req=$req"

    #dict set req -cookies [Cookies parse4server [Dict get? $req cookie]]
    set req [Cookies 4Server $req]
    #set req [Session fetch $req -path /_edit/]

    if {[dict exists $req -session]} {
	# do something with existing session
    } else {
	# this will create a new session on request completion
	dict set req -session created [clock seconds]
    }

    set rsp [Responder Incoming $req -glob -- [dict get $req -path] {
	/*.php -
	/*.wmv -
	/*.exe -
	/cgi-bin/* {
	    # block the originator by IP
	    Block block [dict get $req -ipaddr] "Bogus URL '[dict get $req -path]'"
	    Send [Http Forbidden $req]
	    continue	;# process next request
	}

	/jquery/* -
	/jquery/ {
	    jQ do $req
	}

	/_stats -
	/_stats/* {
	    ::webalizer do $req
	}

	/_sinorca {
	    Http Redir $req "http://[dict get $req host]/_sinorca/"
	}

	/_sinorca/* {
	    # Sinorca page style demo
	    Sinorca ram do $req
	}

	/_wub -
	/_wub/* {
	    # Wub documentation - via the wikit Direct domain
	    ::wub do $req
	}

	/_dub {
	    Http Redir $req "/_dub/"
	}

	/_dub/* {
	    # Dub metakit toy
	    ::dub do $req
	}

	/_doc {
	    Http Redir $req "http://[dict get $req host]/_doc/"
	}

	/_doc/* {
	    # Wub docs
	    ::doc do $req
	}

	/*.jpg -
	/*.gif -
	/*.png -
	/favicon.ico {
	    # silently redirect image files - strip all but tail
	    dict set req -suffix [file tail [dict get $req -path]]
	    ::images do $req
	}
	
	/*.css {
	    # silently redirect css files
	    dict set req -suffix [file tail [dict get $req -path]]
	    ::css do $req
	}

	/*.gz {
	    # silently redirect gz files
	    dict set req -suffix [file tail [dict get $req -path]]
	    ::bin do $req
	}

	/_toc/toggle {
	    # These are wiki-local restful command URLs,
	    # we process them via the ::wikit Direct domain
	    Debug.wikit {toggle TOC invocation [dict get $req -path]}
	    if {[catch {
		set c [Dict get? $req -cookies]
		set toc [Cookies fetch $c -name wiki_toc]
		set toc [expr {![dict get $toc -value]}]
	    } err eo]} {
		Debug.error {toggle new}
		set toc 1
	    }

	    set c [Cookies add $c -name wiki_toc -path /_toc/ -value $toc]
	    Debug.error {toggle: $toc - $c}

	    dict set req -cookies $c
	    Debug.error {Toggle Referer: [Http Referer $req] - $c}
	    set C [subst {
		[<h2> "Menu Toggled"]
		[<p> [<a> href [Http Referer $req] "Return to Wiki"]]
	    }]

	    Http RedirectReferer $req
	}

	/*ie_onload.js {
	    Http CacheableContent [Http Cache $req 100000000] 0 {init();} application/javascript

	    # send out this piddling script to IE users.
	    # See variable head above for how it's invoked.
	    # yet another reason to hate Windows IE
	    # see http://dean.edwards.name/weblog/2005/09/busted/
	    # for the reason for this offence to good taste.
	}

       /_toc/*.js {
	   # Remove if-modified-since, incorrectly sent by Opera
	   dict unset req if-modified-since
            # silently redirect js files
	    if {[catch {
		set toc [Cookies fetch [Dict get? $req -cookies] -name wiki_toc]
		set toc [dict get $toc -value]
	    } x eo]} {
		dict set req -cookies [Cookies add [Dict get? $req -cookies] -name wiki_toc -path /_toc/ -value 1]
                dict set req -suffix [file tail [dict get $req -path]] 
                Http NoCache [Http Ok [::scripts do $req]]
                #Http NoCache [Http Ok $req {} text/javascript]
	    } elseif {!$toc} {
                Http NoCache [Http Ok $req {} text/javascript]
            } else {
                dict set req -suffix [file tail [dict get $req -path]] 
                Http NoCache [Http Ok [::scripts do $req]]
            }
        }

	/robots.txt -
	/*.js {
	    # silently redirect js files
	    dict set req -suffix [file tail [dict get $req -path]]
	    ::scripts do $req
	}

	/_edit/login {
	    # These are wiki-local restful command URLs,
	    # we process them via the ::wikit Direct domain
	    Debug.wikit {direct login invocation [dict get $req -path]}
	    dict set req -suffix /login
	    ::wikit do $req
	}

	/_edit/* {
	    # /_edit domain - wiki-local restful command URL,
	    Debug.wikit {direct invocation1 [dict get $req -path]}
	    set path [file split [dict get $req -path]]
	    set N [lindex $path end]
	    set suffix /[string trimleft [lindex $path end-1] _]
	    dict set req -suffix $suffix
	    dict set req -Query [Query add [Query parse $req] N $N]
	    ::wikit do $req
	}

	/_map/* {
	    set imp [dict get $req -path]
	    if {[info exists ::WikitWub::IMTOC($imp)]} {
		return [Http Redir $req "http://[dict get $req host]/$::WikitWub::IMTOC($imp)"]
	    } else {
		return [Http NotFound $req]
	    }
	}
	
	/_* {
	    # These are wiki-local restful command URLs,
	    # we process them via the ::wikit Direct domain
	    Debug.wikit {direct invocation2 [dict get $req -path]}
	    set path [file split [dict get $req -path]]
	    set N [lindex $path end]
	    set suffix /[string trimleft [lindex $path 1] _]
	    dict set req -suffix $suffix
	    dict set req -Query [Query add [Query parse $req] N $N]
	    ::wikit do $req
	}

	/rss.xml {
	    # generate and return RSS feed
	    Http CacheableContent $req [clock seconds] [WikitRss rss] application/rss+xml
	}

	/ {
	    # need to silently redirect welcome file
	    dict set req -suffix /welcome
	    ::wikit do $req
	}

	//// {
	    # wikit welcome page
	    dict set req -Query [Query parse $req]
	    dict set req -suffix ""
	    dict set req -prefix ""
	    ::WikitWub do $req 0
	}

	default {
	    ::WikitWub do $req [file tail [dict get $req -path]]
	}
    }]

    return [Session store $rsp -path /_edit/]
    #return $rsp
}

#### initialize Block
package require Block
Block init logdir $::config(docroot)

#### initialize Wikit
package require Wikit::Format
package require Wikit::Db
package require Wikit::Cache

if {[info exists ::config(mkmutex)]} {
    set Wikit::mutex $::config(mkmutex)	;# set mutex for wikit writes
}
Wikit::BuildTitleCache

catch {[mk::get wdb.pages!9 page]}

# move utf8 regexp into utf8 package
# utf8 package is loaded by Query
set ::utf8::utf8re $::config(utf8re); unset ::config(utf8re)
set ::roflag 0

# initialize RSS feeder
WikitRss init wdb "Tcler's Wiki" http://wiki.tcl.tk/

#### set up appropriate debug levels
Debug on log 10
Debug on error 10
Debug off query 10
Debug off wikit 10
Debug off direct 10
Debug off convert 10
Debug off cookies 10
Debug off socket 10

#### Source local config script (not under version control)
catch {source [file join [file dirname [info script]] local.tcl]} r eo
Debug.log {RESTART: [clock format [clock second]] '$r' ($eo)}
