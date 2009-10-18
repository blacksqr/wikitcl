#### Source local setup script (not under version control)
if {[file exists [file join [file dirname [info script]] local_setup.tcl]]} {
    source [file join [file dirname [info script]] local_setup.tcl]
}

package require Mk4tcl
package require fileutil
package require struct::queue

#### initialize Wikit
package require Site	;# assume Wub/ is already on the path, or in /usr/lib

lappend auto_path [file dirname [info script]]
package require Sitemap
package require stx
package require Form

package require WDB_sqlite
#package require WDB_mk
package require WikitRss
package require WFormat

package provide WikitWub 1.0

set API(WikitWub) {
    {A Wub interface to tcl wikit}
    base {place where wiki lives (default: same directory as WikitWub.tcl, or parent of starkit mountpoint}
    wikitroot {where the wikit lives (default: $base/data}
    docroot {where ancillary documents live (default: $base/docroot)}
    wikidb {wikit's metakit DB name (default wikit.tkd) - no obvious need to change this.}
    history {history directory}
    readonly {Message which makes the wikit readonly, and explains why.  (default "")}
    motd {message of the day (default "")}
    maxAge {max age of login cookie (default "next month")}
    cookie {name of login cookie (default "wikit_e")}
    language {html natural language (default "en")}
}

namespace eval WikitWub {
    variable readonly ""
    variable pagecaching 1

    # sortable - include javascripts and CSS for sortable table.
    proc sortable {r} {
#	foreach js {common css standardista-table-sorting} {
#	    dict lappend r -headers [<script> src /$js.js]
#	}
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

    proc toolbar_edit_button {action img alt} {
	return [format {<button type='button' class='editbutton' onClick='%1$s("editarea");' onmouseout='popUp(event,"tip_%1$s")' onmouseover='popUp(event,"tip_%1$s")'><img src='/%3$s'></button><span id='tip_%1$s' class='tip'>%2$s</span>} $action $alt $img]
    }

    # page - format up a page using templates
    proc sendPage {r {tname page} {http {NoCache Ok}}} {
	variable templates
	variable titles
	if {$titles($tname) ne ""} {
	    dict set r -title [uplevel 1 subst [list $titles($tname)]]
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
		[div logo [<a> href / class logo [expr {[info exists ::starkit_url]?$::starkit_url:"wiki.tcl.tk"}]]]
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

#		<button type='button' class='editbutton' id='savebutton' onclick='' onmouseout='popUp(event,"tip_save")' onmouseover='popUp(event,"tip_save")'><img src='/page_save.png' alt='Save'></button><span id='tip_save' class='tip'>Save</span>
#		<button type='button' class='editbutton' id='cancelbutton' onclick='editCancel();' onmouseout='popUp(event,"tip_cancel")' onmouseover='popUp(event,"tip_cancel")'><img src='/cancel.png' alt='Cancel'></button><span id='tip_cancel' class='tip'>Cancel</span>
    
    set quick_reference {
	[<br>]
	[<b> "Editing quick-reference:"] <button type='button' id='hidehelpbutton' onclick='hideEditHelp();'>Hide Help</button>
	[<br>]
	<ul>
	<li>[<b> LINK] to [<b> "\[[<a> href ../6 target _blank {Wiki formatting rules}]\]"] - or to [<b> [<a> href http://here.com/ target _blank "http://here.com/"]] - use [<b> "\[http://here.com/\]"] to show as [<b> "\[[<a> href http://here.com/ target _blank 1]\]"]. The string used to display the link can be specified by adding <b><tt>%|%string%|%</tt></b> to the end of the link.</li>
	<li>[<b> BULLETS] are lines with 3 spaces, an asterisk, a space - the item must be one (wrapped) line</li>
	<li>[<b> "NUMBERED LISTS"] are lines with 3 spaces, a one, a dot, a space - the item must be one (wrapped) line</li>
	<li>[<b> PARAGRAPHS] are split with empty lines</li>
	<li>[<b> "UNFORMATTED TEXT"] starts with white space or is enclosed in lines containing <tt>======</tt></li>
	<li>[<b> "FIXED WIDTH FORMATTED"] text is enclosed in lines containing <tt>===</tt></li>
	<li>[<b> HIGHLIGHTS] are indicated by groups of single quotes - use two for [<b> {''}] [<i> italics] [<b> {''}], three for [<b> '''bold''']. Back-quotes can be used for [<b> {`}]<tt>tele-type</tt>[<b> {`}].</li>
	<li>[<b> SECTIONS] can be separated with a horizontal line - insert a line containing just 4 dashes</li>
	<li>[<b> HEADERS] can be specified with lines containing <b>**Header level 1**</b>, <b>***Header level 2***</b> or <b>****Header level 3****</b></li>
	<li>[<b> TABLE] rows can be specified as <b><tt>|data|data|data|</tt></b>, a <b>header</b> row as <b><tt>%|data|data|data|%</tt></b> and background of even and odd rows is <b>colored differently</b> when rows are specified as <b><tt>&amp;|data|data|data|&amp;</tt></b></li>
	<li>[<b> CENTER] an area by enclosing it in lines containing <b><tt>!!!!!!</tt></b></li>
	<li>[<b> "BACK REFERENCES"] to the page being edited can be included with a line containing <b><tt>&lt;&lt;backrefs&gt;&gt;</tt></b>, back references to any page can be included with a line containing <b><tt>&lt;&lt;backrefs:Wiki formatting rules&gt;&gt;</tt></b>, a <b>link to back-references</b> to any page can be included as <b><tt>\[backrefs:Wiki formatting rules\]</tt></b></li>
	</ul>
    }

    set edit_toolbar {
	<button type='submit' class='editbutton' id='savebutton' name='save' value='Save your changes' onmouseout='popUp(event,"tip_save")' onmouseover='popUp(event,"tip_save")'><img src='/page_save.png'></button><span id='tip_save' class='tip'>Save</span>
	<button type='button' class='editbutton' id='previewbutton' onclick='previewPage($N);' onmouseout='popUp(event,"tip_preview")' onmouseover='popUp(event,"tip_preview")'><img src='/page_white_magnify.png'></button><span id='tip_preview' class='tip'>Preview</span>
	<button type='submit' class='editbutton' id='cancelbutton' name='cancel' value='Cancel' onmouseout='popUp(event,"tip_cancel")' onmouseover='popUp(event,"tip_cancel")'><img src='/cancel.png'></button><span id='tip_cancel' class='tip'>Cancel</span>
	&nbsp; &nbsp; &nbsp;
	[toolbar_edit_button bold            text_bold.png           "Bold"]
	[toolbar_edit_button italic          text_italic.png         "Italic"]
	[toolbar_edit_button teletype        text_teletype.png       "TeleType"]
	[toolbar_edit_button heading1        text_heading_1.png      "Heading 1"]
	[toolbar_edit_button heading2        text_heading_2.png      "Heading 2"]
	[toolbar_edit_button heading3        text_heading_3.png      "Heading 3"]
	[toolbar_edit_button hruler          text_horizontalrule.png "Horizontal Rule"]
	[toolbar_edit_button list_bullets    text_list_bullets.png   "List with Bullets"]
	[toolbar_edit_button list_numbers    text_list_numbers.png   "Numbered list"]
	[toolbar_edit_button align_center    text_align_center.png   "Center"]
	[toolbar_edit_button wiki_link       link.png                "Wiki link"]
	[toolbar_edit_button url_link        world_link.png          "World link"]
	[toolbar_edit_button img_link        photo_link.png          "Image link"]
	[toolbar_edit_button code            script_code.png         "Script"]
	[toolbar_edit_button table           table.png               "Table"]
	&nbsp; &nbsp; &nbsp;
	<button type='button' class='editbutton' id='helpbutton' onclick='editHelp();' onmouseout='popUp(event,"tip_help")' onmouseover='popUp(event,"tip_help")'><img src='/help.png'></button><span id='tip_help' class='tip'>Help</span>
    }

    # page sent when editing a page
    template edit {Editing [armour $name]} {
	[div edit {
	    [div header {
		[div logo [expr {[info exists ::starkit_url]?$::starkit_url:"wiki.tcl.tk"}]]
		[If {$as_comment} {
		    [div title "Comment on [tclarmour [Ref $N]]"]
		}]
		[If {!$as_comment} {
		    [div title "Edit [tclarmour [Ref $N]]"]
		}]
		[If {$as_comment} {
		    [div updated "Enter your comment, then press Save below"]
		}]
		[If {!$as_comment} {
		    [div updated "Make your changes, then press Save below"]
		}]
	    }]
	    [div editcontents {
		[set disabled [expr {$nick eq ""}]
		 <form> edit method post action /_/edit/save {
		     [<div> id helptext "[<hr>] [subst $quick_reference]"]
		     [<div> class previewarea_pre id previewarea_pre ""]
		     [<div> class previewarea id previewarea ""]
		     [<div> class previewarea_post id previewarea_post ""]
		     [<div> class toolbar [subst $edit_toolbar]]
		     [<textarea> C id editarea rows 35 cols 72 compact 0 style width:100% [tclarmour $C]]
		     [<hidden> O [list [tclarmour $date] [tclarmour $who]]]
		     [<hidden> _charset_ {}]
		     [<hidden> N $N]
		     [<hidden> A $as_comment]
                     <input name='save' type='submit' value='Save your changes'>
		     <input name='cancel' type='submit' value='Cancel'>
		     <button type='button' id='previewbutton' onclick='previewPage($N);'>Preview</button>
		     <button type='button' id='helpbutton' onclick='editHelp();'>Help</button>
		 }]
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
	[<p> "Please choose a nickname that your edit will be identified by."]
	[if {0} {[<p> "You can optionally enter a password that will reserve that nickname for you."]}]
	[<form> login method post action /_/edit/login {
	    [<fieldset> login title Login {
		[<text> nickname title "Nickname"]
		[<input> name save type submit value "Login" {}]
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
	[<form> search method get action /_/search {
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
	[<p> [<i> "Please restart a new [Ref /_/edit?N=$N edit] and merge your version (which is shown in full below.)"]]
	[<p> "Got '$O' expected '$X'"]
	[<hr> size 1]
	[<p> [<pre> [armour $C]]]
	[<hr> size 1]
    }

    variable searchForm [string map {%S $search %N $N} [<form> search method get action /_/search {
	[<fieldset> sfield title "Construct a new search" {
	    [<legend> "Enter a Search Phrase"]
	    [<text> S title "Append an asterisk (*) to search page contents" [armour %S]]
	    [<checkbox> SC title "search page contents" value 1; set _disabled ""]
	    [<hidden> _charset_]
	    [<hidden> N %N]
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
	    if {$i ne ""} {
		append m "<li>$i</li>"
	    }
	}
	append m "</ul>"
    }

    # return a search form
    proc searchF {} {
	set result [<form> searchform method get action /_/search {
	    [<text> S id searchtxt onfocus {clearSearch();} onblur {setSearch();} "Search in titles"]
	    [<hidden> _charset_ ""]
	}]
	append result \n [<form> gsearchform method get action /_/gsearch {
	    [<text> S id googletxt onfocus {clearGoogle();} onblur {setGoogle();} "Search in pages"]
	    [<hidden> _charset_ ""]
	}] \n
	return $result
    }

    proc gsearchF {Q} {
	set result [<form> searchform action /_/search {
	    [<text> S id searchtxt onfocus {clearSearch();} onblur {setSearch();} "Search in titles"]
	    [<hidden> _charset_ ""]
	}]
	append result \n [<form> gsearchform method get action /_/gsearch {
	    [<text> S id googletxt onfocus {clearGoogle();} onblur {setGoogle();} [tclarmour $Q]]
	    [<hidden> _charset_ ""]
	}] \n
	return $result
    }

    variable maxAge "next month"	;# maximum age of login cookie
    variable cookie "wikit_e"		;# name of login cookie

    variable htmlhead {<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN" "http://www.w3.org/TR/html4/loose.dtd">}
    variable language "en"	;# language for HTML

    # header sent with each page
    #<meta name='robots' content='index,nofollow' />
    variable head [subst {

	[<link> rel stylesheet             href "/wikit_screen.css"       media "screen"   type "text/css" title "With TOC"]
	[<link> rel "alternate stylesheet" href "/wikit_screen_notoc.css" media "screen"   type "text/css" title "Without TOC"]
	[<link> rel stylesheet             href "/wikit_print.css"        media "print"    type "text/css"]
	[<link> rel stylesheet             href "/wikit_handheld.css"     media "handheld" type "text/css"]
	[<link> rel stylesheet             href "/tooltips.css"                            type "text/css"]
	
	[<link> rel alternate type "application/rss+xml" title RSS href /rss.xml]
	<!--\[if lte IE 6\]>
	[<style> media all "@import '/ie6.css';"]
	<!\[endif\]-->
	<!--\[if gte IE 7\]>
	[<style> media all "@import '/ie7.css';"]
	<!\[endif\]-->
	[<script> {
	    function init() {
		// quit if this function has already been called
		if (arguments.callee.done) return;

		// flag this function so we don't do the same thing twice
		arguments.callee.done = true;

		try {
		    document.getElementById("googletxt").value;
		    googleQuery();
		}
		catch (e){}

		//try {
		    //    checkTOC();
		    //} catch (err) {
			//    /* nothing */
			//}
	    };

	    /* for Mozilla */
	    if (document.addEventListener) {
		document.addEventListener("DOMContentLoaded", init, false);
	    }
	    
	    /* for Internet Explorer */
	    /*@cc_on @*/
	    /*@if (@_win32)
	    document.write("<script defer src='/_/ie_onload1.JS'><\/script>");
	    /*@end @*/
	    
	    /* for other browsers */
	    window.onload = init;
	}]
	<meta name="verify-v1" content="89v39Uh9xwxtWiYmK2JcYDszlGjUVT1Tq0QX+7H8AD0=">
    }]

    # protected pages
    variable protected
    array set protected {Search 2 Changes 4 HoneyPot 5 Something 7 TOC 8 Init 9}
    foreach {n v} [array get protected] {
	set protected($v) $n
    }

    # html suffix to be sent on every page
    variable htmlsuffix [<script> src /wiki.js] \n

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
	    set title [dict get? $rsp -title]
	    if {$title ne ""} {
		append content [<title> $title] \n
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
		append content [join [dict get $rsp -postload] \n]
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
	variable docroot
	set p http://[Url host $r]/
	set map {}
	append map [Sitemap location $p "" mtime [file mtime $docroot/html/welcome.html] changefreq weekly] \n
	append map [Sitemap location $p 4 mtime [clock seconds] changefreq always priority 1.0] \n

	foreach record [WDB AllPages] {
	    set id [dict get $record id]
	    if {$id < 11} continue
	    append map [Sitemap location $p $id mtime [dict get $record date]] \n
	}

	return [Http NoCache [Http Ok $r [Sitemap sitemap $map] text/xml]]
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

    proc edit_activity {N} {

	set pcdate [WDB GetPage $N date]
	set edate [expr {$pcdate-10*86400}]
	set first 1
	set activity 0.0

	foreach record [WDB Changes $N] {
	    dict with record {
		set changes [WDB ChangeSetSize $N $version]
		set activity [expr {$activity + $changes * $delta / double([clock seconds] - $pcdate)}]
		set pcdate $date
		set first 0
	    }
	    if {$pcdate<$edate} {
		break
	    }
	}

	if {$first} {
	    set activity 10000
	} else {
	    set activity [expr {int($activity * 10000.0)}]
	}

	set activity [string length $activity]
	return $activity
    }

    proc WhoUrl { who {ip 1} } {
	if {$who ne "" &&
	    [regexp {^(.+)[,@](.*)} $who - who_nick who_ip]
	    && $who_nick ne ""
	} {
	    set who "[<a> href /[WDB LookupPage $who_nick] $who_nick]"
	    if {$ip} {
		append who @[<a> rel nofollow target _blank href http://ip-lookup.net/index.php?ip=$who_ip $who_ip]
	    }
	}
	return $who
    }

    # Special page: Recent Changes.
    variable delta [subst \u0394]
    variable delta [subst \u25B2]
    proc RecentChanges {} {
	variable delta
	set results {}
	set result {}
	set lastDay 0
	set threshold [expr {[clock seconds] - 7 * 86400}]
	set deletesAdded 0
	set activityHeaderAdded 0

	foreach record [WDB RecentChanges $threshold] {
	    puts stderr "RC: $record"
	    dict with record {}

	    # these are fake pages, don't list them
	    if {$id < 11} continue

	    # only report last change to a page on each day
	    set day [expr {$date/86400}]

	    # insert a header for each new date
	    if {$day != $lastDay} {

		if { [llength $result] } {
		    lappend results [list2plaintable $result {rc1 rc2 rc3} rctable]
		    set result {}

		    if { !$deletesAdded } {
			lappend results [<p> [<a> class cleared href /_/cleared "Cleared pages (title and/or page)"]]
			set deletesAdded 1
		    }
		}

		lappend results [<p> ""]
		set datel [list "[<b> [clock format $date -gmt 1 -format {%Y-%m-%d}]] [<span> class day [clock format $date -gmt 1 -format %A]]" ""]
		if {!$activityHeaderAdded} {
		    lappend datel "Activity"
		    set activityHeaderAdded 1
		} else {
		    lappend datel ""
		}
		lappend result $datel
		set lastDay $day
	    }

	    set actimg "<img class='activity' src='activity.png' alt='*' />"

	    lappend result [list "[<a> href /$id [armour $name]] [<a> class delta rel nofollow href /_/diff?N=$id#diff0 $delta]" [WhoUrl $who] [<div> class activity [<a> class activity rel nofollow href /_/summary?N=$id [string repeat $actimg [edit_activity $id]]]]]
	}

	if { [llength $result] } {
	    lappend results [list2plaintable $result {rc1 rc2 rc3} rctable]
	    if { !$deletesAdded } {
		lappend results [<p> [<a> href /_/cleared "Cleared pages (title and/or page)"]]
	    }
	}

	lappend results [<p> "generated [clock format [clock seconds]]"]
	set R [join $results \n]

	return $R
    }

    proc /cleared { r } {
	if {[dict get? $r -ua_class] eq "robot"} {
	    return [robot $r]
	}
	set results ""

	set lastDay 0
	foreach record [WDB Cleared] {
	    dict with record {}

	    # these are fake pages, don't list them
	    if {$id < 11} continue

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
		set link [<a> href /$id [armour $name]]
	    } else {
		set link [<a> href /$id $id]
	    }
	    append link [<span> class dots ". . ."]
	    append link [<span> class nick [WhoUrl $who]]
	    append link [<span> class dots ". . ."]
	    append link [<span> class nick [clock format $date -gmt 1 -format %T]]
	    append link [<span> class dots ". . ."]
	    append link [<a> class delta href /_/history?N=$id history]
	    lappend results [<li> $link]
	}
	if {$lastDay} {
	    lappend results </ul>
	}

	set name "Cleared pages"
	set Title "Cleared pages"
	set T ""
	set N 0
	set updated ""
        set menu [menus Home Recent Help]
	set footer [menus Home Recent Help Search]

	set C [join $results "\n"]
	variable TOC
	return [sendPage $r]
    }

    proc get_page_with_version {N V {A 0}} {
	Debug.wikit {get_page_with_version N:$N V:$V A:$A}
	if {$A} {
	    set aC [WDB AnnotatePageVersion $N $V]
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
	} elseif {$V >= 0} {
	    set C [WDB GetPageVersion $N $V]
	} else {
	    set C [WDB GetContent $N]
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
	    lappend n [string map {\t "        "} $nl]
	}
	return $n
    }

    proc summary_diff { N V W {rss 0} } {
	Debug.wikit {summary_diff N:$N V:$V W:$W rss:$rss}
	set t1 [split [get_page_with_version $N $V 0] "\n"]
	set W [expr {$V-1}]
	set t2 [split [get_page_with_version $N $W 0] "\n"]
	set uwt1 [unWhiteSpace $t1]
	set uwt2 [unWhiteSpace $t2]
	set p1 0
	set p2 0
	set C ""
	foreach {l1 l2} [::struct::list::LlongestCommonSubsequence $uwt1 $uwt2] {
	    foreach i1 $l1 i2 $l2 {
		while { $p1 < $i1 } {
		    if {$rss} {
			append C "[lindex $t1 $p1]\n"
		    } else {
			append C ">>>>>>n;$N;$V;;\n[lindex $t1 $p1]\n<<<<<<\n"
		    }
		    incr p1
		}
		while { $p2 < $i2 } {
		    if {$rss} {
			#			append C ">>>>>>o;$N;$W;;\n[lindex $t2 $p2]\n<<<<<<\n"
		    } else {
			append C ">>>>>>o;$N;$W;;\n[lindex $t2 $p2]\n<<<<<<\n"
		    }
		    incr p2
		}
		incr p1
		incr p2
	    }
	}
	while { $p1 < [llength $t1] } {
	    if {$rss} {
		append C "[lindex $t1 $p1]\n"
	    } else {
		append C ">>>>>>n;$N;$V;;\n[lindex $t1 $p1]\n<<<<<<\n"
	    }
	    incr p1
	}
	while { $p2 < [llength $t2] } {
	    if {$rss} {
		#		append C ">>>>>>o;$N;$V;;\n[lindex $t2 $p2]\n<<<<<<\n"
	    } else {
		append C ">>>>>>o;$N;$V;;\n[lindex $t2 $p2]\n<<<<<<\n"
	    }
	    incr p2
	}

	return $C
    }

    proc robot {r} {
	set content [<h1> "We think you're a robot"]
	append content [<p> "If we're mistaken, please accept our apologies.  We don't permit robots to access our more computationally expensive pages."]
	append content [<p> "We also require cookies to be enabled on your browser to access these pages."]

	return [Http Forbidden $r $content]
    }

    proc /summary {r N {D 10}} {
	if {[dict get? $r -ua_class] eq "robot"} {
	    return [robot $r]
	}

	variable delta

	set N [file rootname $N]	;# it's a simple single page
	if {![string is integer -strict $N] || $N < 0 || $N >= [WDB PageCount]} {
	    return [Http NotFound $r]
	}
	if {![string is integer -strict $D]} {
	    set D 10
	}

	set R ""
	set n 0
	lassign [WDB GetPage $N date name who] pcdate name pcwho
	set page [WDB GetContent $N]
	set V [WDB Versions $N]	;# get #version for this page

	append R <ul>\n
	if {$V==0} {
	    append R [<li> "$pcwho, [clock format $pcdate], New page"] \n
	} else {
	    # get changes for current page in last D days
	    set edate [expr {$pcdate-$D*86400}]
	    foreach record [WDB Changes $N $edate] {
		dict update record date cdate who cwho delta cdelta version version {}
		set changes [WDB ChangeSetSize $N $version]
		append R [<li> "[WhoUrl $pcwho], [clock format $pcdate], #chars: $cdelta, #lines: $changes"] \n
		set C [summary_diff $N $V [expr {$V-1}]]
		lassign [WFormat StreamToHTML [WFormat TextToStream $C] / ::WikitWub::InfoProc] C U T BR
		append R $C
		set pcdate $cdate
		set pcwho $cwho
		incr V -1
		if {$V < 1} break
	    }
	}
	append R </ul> \n
	
	set menu {}
	variable menus
	variable TOC
	set updated "Edit summary"
	set menu [menus Home Recent Help HR]
	lappend menu [Ref /_/history?N=$N History]
	lappend menu [Ref /_/summary?N=$N "Edit summary"]
	lappend menu [Ref /_/diff?N=$N "Last change"]
	lappend menu [Ref /_/diff?N=$N&T=1&D=1 "Changes last day"]
	lappend menu [Ref /_/diff?N=$N&T=1&D=7 "Changes last week"]
	set footer [menus Home Recent Help Search]
	set T "" ;# Do not show page TOC, can be one of the diffs.
	set C $R
	set Title [Ref $N]
	set name "Edit summary for $name"
	return [sendPage $r page]
	#return [sendPage [Http CacheableContent $r [clock seconds]] page DCache]
    }

    proc /diff {r N {V -1} {D -1} {W 0} {T 0}} {
	# If T is zero, D contains version to compare with
	# If T is non zero, D contains a number of days and /diff must
	Debug.wikit {/diff N:$N V:$V D:$D W:$W T:$T}

	if {[dict get? $r -ua_class] eq "robot"} {
	    return [robot $r]
	}
    
	set ext [file extension $N]	;# file extension?
	set N [file rootname $N]	;# it's a simple single page

	if {![string is integer -strict $N]
	    || ![string is integer -strict $V]
	    || ![string is integer -strict $D]
            || $N < 0
	    || $N >= [WDB PageCount]
	    || $ext ni {"" .txt .str .code}
	} {
	    return [Http NotFound $r]
	}

	if {![string is integer -strict $T]} {
	    set T 0
	}

	set nver [WDB Versions $N]

	if { $V > $nver || ($T == 0 && $D > $nver) } {
	    return [Http NotFound $r]
	}

	if {$V < 0} {
	    set V $nver	;# default
	}
    
	# If T is zero, D contains version to compare with
	# If T is non zero, D contains a number of days and /diff must
	# search for a version $D days older than version $V
	set updated ""
	if {$T == 0} {
	    if {$D < 0} {
		set D [expr {$nver - 1}]	;# default
	    }
	} else {
	    if {$V >= $nver} {
		set vt [WDB GetPage $N date]
	    } else {
		set vt [WDB GetChange $N $V date]
	    }
	    if {$D < 0} {
		set D 1
	    }

	    if {$V == $nver} {
		if {$D==1} {
		    set updated "Changes last day"
		} elseif {$D==7} {
		    set updated "Changes last week"
		} else {
		    set updated "Changes last $D days"
		}
	    }

	    # get most recent change
	    set dt [expr {$vt-$D*86400}]
	    set D [WDB MostRecentChange $N $dt]
	}

	set name [WDB GetPage $N name]

	set t1 [split [get_page_with_version $N $V] "\n"]

	if {!$W} { set uwt1 [unWhiteSpace $t1] } else { set uwt1 $t1 }

	set t2 [split [get_page_with_version $N $D] "\n"]
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

	set Title [Ref $N]
	if {$V >= 0} {
	    switch -- $ext {
		.txt {
		    return [Http NoCache [Http Ok $r $C text/plain]]
		}
		.code {
		    set C [WFormat TextToStream $C 0 0 0]
		    set C [WFormat StreamToTcl $name $C ::WikitWub::InfoProc]
		    return [Http NoCache [Http Ok $r $C text/plain]]
		}
		.str {
		    set C [WFormat TextToStream $C]
		    return [Http NoCache [Http Ok $r $C text/plain]]
		}
		default {
		    set Title [Ref $N]
		    set name "Difference between version $V and $D for $name"
		    if { $W } {
			set C [WFormat ShowDiffs $C]
		    } else {
			lassign [WFormat StreamToHTML [WFormat TextToStream $C] / ::WikitWub::InfoProc] C U T BR
		    }
		    set tC [<span> class newwikiline "Text added in version $V is highlighted like this"]
		    append tC , [<span> class oldwikiline "text deleted from version $D is highlighted like this"]
		    if {!$W} {
			append tC , [<span> class whitespacediff "text with only white-space differences is highlighted like this"]
		    }
		    set C "$tC<hr>$C"
		}
	    }
	}
    
	variable menus
	variable TOC
	if {![string length $updated]} {
	    set updated "Difference between version $V and $D"
	}
	set menu [menus Home Recent Help HR]
	lappend menu [Ref /_/history?N=$N History]
	lappend menu [Ref /_/summary?N=$N "Edit summary"]
	lappend menu [Ref /_/diff?N=$N "Last change"]
	lappend menu [Ref /_/diff?N=$N&T=1&D=1 "Changes last day"]
	lappend menu [Ref /_/diff?N=$N&T=1&D=7 "Changes last week"]
	set footer [menus Home Recent Help Search]
	set T "" ;# Do not show page TOC, can be one of the diffs.
	return [sendPage $r]
    }

    proc /revision {r N {V -1} {A 0}} {
	Debug.wikit {/page $args}

	if {[dict get? $r -ua_class] eq "robot"} {
	    return [robot $r]
	}

	set ext [file extension $N]	;# file extension?
	set N [file rootname $N]	;# it's a simple single page

	if {![string is integer -strict $N]
	    || ![string is integer -strict $V]
	    || ![string is integer -strict $A]
            || $N < 0
	    || $N >= [WDB PageCount]
	    || $V < 0
	    || $ext ni {"" .txt .str .code}
	} {
	    return [Http NotFound $r]
	}

	set nver [WDB Versions $N]
	if {$V > $nver} {
	    return [Http NotFound $r]
	}

	variable menus
	set menu [menus Home Recent Help HR]
	lappend menu [Ref /_/history?N=$N History]

	set name [WDB GetPage $N name]
	if {$V >= 0} {
	    switch -- $ext {
		.txt {
		    set C [get_page_with_version $N $V $A]
		    return [Http NoCache [Http Ok $r $C text/plain]]
		}
		.code {
		    set C [WFormat TextToStream [get_page_with_version $N $V $A] 0 0 0]
		    set C [WFormat StreamToTcl $name $C ::WikitWub::InfoProc]
		    return [Http NoCache [Http Ok $r $C text/plain]]
		}
		.str {
		    set C [WFormat TextToStream [get_page_with_version $N $V $A]]
		    return [Http NoCache [Http Ok $r $C text/plain]]
		}
		default {
		    set C [get_page_with_version $N $V $A]
		    if {$A} {
			set Title "Annotated version $V of [Ref $N]"
			set name "Annotated version $V of $name"
		    } else {
			set Title "Version $V of [Ref $N]"
			set name "Version $V of $name"
		    }
		    lassign [WFormat StreamToHTML [WFormat TextToStream $C] / ::WikitWub::InfoProc] C U T BR
		    if { $V > 0 } {
			lappend menu [Ref "/_/revision?N=$N&V=[expr {$V-1}]&A=$A" "Previous version"]
		    }
		    if { $V < $nver } {
			lappend menu [Ref "/_/revision?N=$N&V=[expr {$V+1}]&A=$A" "Next version"]
		    }
		    if { $A } {
			lappend menu [Ref "/_/revision?N=$N&V=$V&A=0" "Not annotated"]
		    } else {
			lappend menu [Ref "/_/revision?N=$N&V=$V&A=1" "Annotated"]
		    }
		}
	    }
	}

	set footer [menus Home Recent Help Search]
	set updated ""
	set T ""
	variable TOC
	return [sendPage $r]
    }

    # /history - revision history
    proc /history {r N {S 0} {L 25}} {
	Debug.wikit {/history $N $S $L}

	if {[dict get? $r -ua_class] eq "robot"} {
	    return [robot $r]
	}

	if {![string is integer -strict $N]
	    || ![string is integer -strict $S]
	    || ![string is integer -strict $L]
	    || $N >= [WDB PageCount]
	    || $S < 0
	    || $L <= 0} {
	    return [Http NotFound $r]
	}

	set name "Change history of [WDB GetPage $N name]"
	set Title "Change history of [Ref $N]"

	set menu [menus Home Recent Help HR]
	set C ""
	#	set links ""
	if {$S > 0} {
	    set pstart [expr {$S - $L}]
	    if {$pstart < 0} {
		set pstart 0
	    }
	    lappend menu [<a> href "history?N=$N&S=$pstart&L=$L" "Previous $L"]
	    #	    append links [<a> href "$N?S=$pstart&L=$L" "Previous $L"]
	}
	set nstart [expr {$S + $L}]
	set nver [WDB Versions $N]
	if {$nstart < $nver} {
	    #	    if {$links ne {}} {
	    #		append links { - }
	    #	    }
	    lappend menu [<a> href "history?N=$N&S=$nstart&L=$L" "Next $L"]
	    #	    append links [<a> href "$N?S=$nstart&L=$L" "Next $L"]
	}
	set footer [menus Home Recent Help Search]
	#	if {$links ne {}} {
	#	    append C <p> $links </p> \n
	#	}
	set versions [WDB ListPageVersions $N $L $S]
	set name [WDB GetPage $N name]
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
	    set curr $nver
	    if { $rowcnt % 2 } {
		append C "<tr class='odd'>"
	    } else {
		append C "<tr class='even'>"
	    }
	    append C [<td> class Rev [<a> href "/_/revision?N=$N&V=$vn" rel nofollow $vn]]
	    append C [<td> class Date [clock format $date -format "%Y-%m-%d %T" -gmt 1]]
	    append C [<td> class Who [WhoUrl $who]]
	    
	    if { $prev >= 0 } {
		append C [<td> class Line1 [<a> href "/_/diff?N=$N&V=$vn&D=$prev#diff0" $prev]]
	    } else {
		append C <td></td>
	    }
	    if { $next <= $nver } {
		append C [<td> class Line2 [<a> href "/_/diff?N=$N&V=$vn&D=$next#diff0" $next]]
	    } else {
		append C <td></td>
	    }
	    if { $vn != $curr } {
		append C [<td> class Line3 [<a> href "/_/diff?N=$N&V=$curr&D=$vn#diff0" Current]]
	    } else {
		append C <td></td>
	    }

	    if { $prev >= 0 } {
		append C [<td> class Word1 [<a> href "/_/diff?N=$N&V=$vn&D=$prev&W=1#diff0" $prev]]
	    } else {
		append C <td></td>
	    }
	    if { $next <= $nver } {
		append C [<td> class Word2 [<a> href "/_/diff?N=$N&V=$vn&D=$next&W=1#diff0" $next]]
	    } else {
		append C <td></td>
	    }
	    if { $vn != $curr } {
		append C [<td> class Word3 [<a> href "/_/diff?N=$N&V=$curr&D=$vn&W=1#diff0" Current]]
	    } else {
		append C <td></td>
	    }
	    
	    append C [<td> class Annotated [<a> href "/_/revision?N=$N&V=$vn&A=1" $vn]]
	    append C [<td> class WikiText [<a> href "/_/revision?N=$N.txt&V=$vn" $vn]]
	    append C </tr> \n
	    incr rowcnt
	}
	append C </tbody></table> \n

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
	    set name [WDB GetPage $page name]
	    if {$name eq ""} {
		set name $page
	    }
	}
	return [<a> href /[string trimleft $url /] {*}$args [armour $name]]
    }

    variable menus
    variable bullet " &bull; "

    # Init common menu items
    set menus(Home)   [<a> href "/" Home]
    set menus(Recent) [Ref 4 "Recent changes"]
    set menus(Help)   [Ref 3 "Help"]
    set menus(HR)     <br>
    set menus(Search) [Ref 2 "Search"]
    set redir {meta: http-equiv='refresh' content='10;url=$url'

	<h1>Redirecting to $url</h1>
	<p>$content</p>
    }

    proc menus { args } {
        variable menus
	set m {}
	foreach arg $args {
	    if {$arg ne ""} {
		lappend m $menus($arg)
	    }
	}
	return $m
    }

    proc redir {r url content} {
	variable redir
	return [Http NoCache [Http SeeOther $r $url [subst $redir]]]
    }

    proc /who {r} {
	set C [Html dict2table [dict get $r -session] {who edit}]
	return [Http NoCache [Http Ok [sortable $r] $C x-text/wiki]]
    }

    proc /edit/login {r {nickname ""} {R ""}} {
	set path [file split [dict get $r -path]]
	set N [lindex $path end]
	set suffix /[string trimleft [lindex $path end-1] _]
	dict set r -suffix $suffix
	dict set r -Query [Query add [Query parse $r] N $N]

	# cleanse nickname
	regsub -all {[^A-Za-z0-0_]} $nickname {} nickname

	if {$nickname eq ""} {
	    # this is a call to /login with no args,
	    # in order to generate the /login page
	    Debug.wikit {/login - redo with referer}
	    set R [Http Referer $r]
	    return [sendPage $r login]
	}

	if {[dict exists $r -cookies]} {
	    set cdict [dict get $r -cookies]
	} else {
	    set cdict [dict create]
	}
	set dom [dict get $r -host]

	# include an optional expiry age
	variable maxAge
	if {$maxAge ne ""} {
	    set age [list -expires $maxAge]
	} else {
	    set age {}
	}

	variable cookie
	Debug.wikit {/login - created cookie $nickname with R $R}
	set cdict [Cookies add $cdict -path /_/ -name $cookie -value $nickname {*}$age]

	dict set r -cookies $cdict
	if {$R eq ""} {
	    set R [Http Referer $r]
	    if {$R eq ""} {
		set R "http://[dict get $r host]/"
	    }
	}

	return [redir $r $R [<a> href $R "Created Account"]]
    }

    proc invalidate {r url} {
	dict set r -path "/[string trimright $url /]"
	set url [Url url $r]
	Debug.wikit {invalidating $url} 3
	return [Cache delete $url]
    }

    proc locate {page {exact 1}} {
	Debug.wikit {locate '$page'}
	variable cnt

	# try exact match on page name
	if {[string is integer -strict $page]} {
	    Debug.wikit {locate - is integer $page}
	    return $page
	}

	set N [WDB PageByName $page]

        # No matches, retry with decoded string
        if {[llength $N] == 0} {
	    set N [WDB PageByName [Query decode $page]]
	}

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
		if {[string first \[ $page] < 0} {
		    regsub -all {[A-Z]} $page "\\\[&\[string tolower &\]\\\]" temp
		    set temp "*[subst -novariable $temp]*"
		    set N [WDB PageGlobName $temp]
		}
		if {[llength $N] == 1} {
		    # glob search was unambiguous
		    Debug.wikit {locate - unique by title search - $N}
		    return $N
		}
	    }
	}

	# ambiguous match or no match - make it a keyword search
	Debug.wikit {locate - kw search}
	return 2	;# the search page
    }

    proc /search {r {S ""} args} {
	if {[dict get? $r -ua_class] eq "robot"} {
	    return [robot $r]
	}

	if {$S eq "" && [llength $args] > 0} {
	    set S [lindex $args 0]
	}

	Debug.wikit {/search: '$S'}
	dict set r -prefix "/$S"
	dict set r -suffix $S

	dict append r -path /2
	return [WikitWub do $r]
    }

    proc /gsearch {r {S ""}} {
	set name "Search"
	set Title "Search"
	set updated "powered by <img class='branding' src='http://www.google.com/uds/css/small-logo.png'</img>"
	set C [<script> src "http://www.google.com/jsapi?key=$::google_jsapi_key"]
	append C \n
	append C [<script> {google.load('search', '1');}]
	append C \n
	variable TOC
	variable gsearch 1
	variable query $S
	set menu [menus Home Recent Help]
	set footer [menus Home Recent Help]
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
	if {[dict get? $r -ua_class] eq "robot"} {
	    return [robot $r]
	}

	set O [string map {\t "        "} [encoding convertfrom utf-8 $O]]
	set C [WFormat TextToStream $O]
	lassign [WFormat StreamToHTML $C / ::WikitWub::InfoProc 1] C U T BR
	set C [string map [list "<<TOC>>" [<p> [<b> [<i> "Table of contents will be inserted here."]]]] $C]
	return [sendPage $r preview_tc]
    }

    proc /edit/save {r N C O A save cancel preview } {

	puts "edit-save@[clock seconds] start"

	if {[dict get? $r -ua_class] eq "robot"} {
	    puts "edit-save@[clock seconds] robot"
	    return [robot $r]
	}

	Debug.wikit {/edit/save $N}
	if { [string tolower $cancel] eq "cancel" } {
	    set url http://[Url host $r]/$N
	    puts "edit-save@[clock seconds] canceled"
	    return [redir $r $url [<a> href $url "Canceled page edit"]]
	}

	variable readonly
	if {$readonly ne ""} {
	    puts "edit-save@[clock seconds] read-only"
	    return [sendPage $r ro]
	}

	if {![string is integer -strict $N]} {
	    puts "edit-save@[clock seconds] $N no integer"
	    return [Http NotFound $r]
	}
	if {$N >= [WDB PageCount]} {
	    puts "edit-save@[clock seconds] $N not found"
	    return [Http NotFound $r]
	}

	lassign [WDB GetPage $N name date who] name date who
	set page [WDB GetContent $N]
	if {$name eq ""} {
	    puts "edit-save@[clock seconds] $N not a valid page"
	    return [Http NotFound $er [subst {
		[<h2> "$N is not a valid page."]
		[<p> "[armour $r]([armour $eo])"]
	    }]]
	}

	# is the caller logged in?
	set nick [who $r]
	set when [expr {[dict get $r -received] / 1000000}]

	Debug.wikit {/edit/save N:$N [expr {$C ne ""}] who:$nick when:$when - modified:"$date $who" O:$O }

	# if there is new page content, save it now
	variable protected
	set url http://[Url host $r]/$N
	if {$N ne ""
	    && $C ne ""
	    && ![info exists protected($N)]
	} {

	    puts "edit-save@[clock seconds] check conflicts"

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
		    puts "edit-save@[clock seconds] conflict"
		    return [sendPage $r conflict {NoCache Conflict}]
		}
	    }

	    puts "edit-save@[clock seconds] normalize"

	    # newline-normalize content
	    set C [string map {\r\n \n \r \n} $C]

	    puts "edit-save@[clock seconds] check utf8"
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
		puts "edit-save@[clock seconds] badutf"
		return [sendPage $r badutf]
	    }

	    puts "edit-save@[clock seconds] check if only commenting"
	    # save the page into the db.
	    set who $nick@[dict get $r -ipaddr]
	    if {[string is integer -strict $A] && $A} {
		# Look for category at end of page using following styles:
		# ----\n[Category ...]
		# ----\n!!!!!!\n%|Category...|%\n!!!!!!
		set Cl [split [string trimright [WDB GetContent $N] \n] \n]
		if {[lindex $Cl end] eq "!!!!!!" && [lindex $Cl end-2] eq "!!!!!!" && [string match "----*" [lindex $Cl end-3]] && [string match "%|*Category*|%" [lindex $Cl end-1]]} {
		    set Cl [linsert $Cl end-4 ---- "'''\[$nick\] - [clock format [clock seconds] -format {%Y-%m-%d %T}]'''" {} $C {}]
		} elseif {[string match "<<categories>>*" [lindex $Cl end]]} {
		    set Cl [linsert $Cl end-1 ---- "'''\[$nick\] - [clock format [clock seconds] -format {%Y-%m-%d %T}]'''" {} $C {}]
		} else {
		    lappend Cl ---- "'''\[$nick\] - [clock format [clock seconds] -format {%Y-%m-%d %T}]'''" {} $C
		}
		set C [join $Cl \n]
	    }
	    puts "edit-save@[clock seconds] remove RA"
	    set C [string map {\t "        " "Robert Abitbol" unperson RobertAbitbol unperson Abitbol unperson} $C]
	    puts "edit-save@[clock seconds] check if real changes"
	    if {$C eq [WDB GetContent $N]} {
		Debug.wikit {No change, not saving  $N}
		puts "edit-save@[clock seconds] unchanged"
		return [redir $r $url [<a> href $url "Unchanged Page"]]
	    }
	    Debug.wikit {SAVING $N}

	    puts "edit-save@[clock seconds] save it"
	    if {[catch {
		WDB SavePage $N $C $who $name $when
	    } err eo]} {
		set readonly $err
	    }
	    puts "edit-save@[clock seconds] check pagecaching"
	    variable pagecaching
	    if {$pagecaching} {
		variable pagecache
		if {[$pagecache exists id $N]} {
		    $pagecache delete [$pagecache find id $N]
		}
		if {[$pagecache exists id 4]} {
		    $pagecache delete [$pagecache find id 4]
		}
	    }

	    puts "edit-save@[clock seconds] invalidate"
	    # Only actually save the page if the user selected "save"
	    invalidate $r $N
	    invalidate $r 4
	    invalidate $r _ref/$N
	    invalidate $r rss.xml; WikitRss clear
	    invalidate $r _summary/$N

	    # if this page did not exist before:
	    # remove all referencing pages.
	    #
	    # this makes sure that cache entries point to a filled-in page
	    # from now on, instead of a "[...]" link to a first-time edit page
	    puts "edit-save@[clock seconds] invalidate refs"
	    if {$date == 0} {
		foreach from [WDB ReferencesTo $N] {
		    invalidate $r $from
		}
	    }
	    puts "edit-save@[clock seconds] done saving"
	}

	Debug.wikit {save done $N}
	# instead of redirecting, return the generated page with a Content-Location tag
	#return [do $r $N]
	puts "edit-save@[clock seconds] done"
	return [redir $r $url [<a> href $url "Edited Page"]]
    }

    proc /map {r imp args} {
	if {[info exists ::WikitWub::IMTOC($imp)]} {
	    return [Http Redir $r "http://[dict get $r host]/$::WikitWub::IMTOC($imp)"]
	} else {
	    return [Http NotFound $r]
	}
    }

    # /reload - direct url to reload numbered pages from fs
    proc /reload {r} {
	foreach {} {}
    }
    
    # called to generate an edit page
    proc /edit {r N A args} {
	if {[dict get? $r -ua_class] eq "robot"} {
	    return [robot $r]
	}

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
	if {$N >= [WDB PageCount]} {
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

	lassign [WDB GetPage $N name date who] name date who ;# get the last change author

	set who_nick ""
	regexp {^(.+)[,@]} $who - who_nick
	variable as_comment 0
	if {[string is integer -strict $A] && $A} {
	    set as_comment 1
	    set C [armour "<enter your comment here, a header with nick-name and timestamp will be insert for you>"]
	} else {
	    set C [armour [WDB GetContent $N]]
	    if {$C eq ""} {
		if {[info exists ::starkit_edit_template]} {
		    set C $::starkit_edit_template
		} else {
		    set C "This is an empty page.\n\nEnter page contents here or click cancel to leave it empty.\n\n<<categories>>Enter Category Here\n"
		}
	    }
	}

	variable quick_reference
	variable edit_toolbar
	return [sendPage $r edit]
    }

    proc /motd {r} {
	variable motd
	variable docroot

	puts "\n\n\n\n\nmotd: [file join $docroot motd]\n\n\n\n\n"

	catch {set motd [::fileutil::cat [file join $docroot motd]]}
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
	variable docroot

	set tocf [file join $docroot TOC]

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
	    lassign [WFormat FormatWikiToc $TOC] TOC IMTOCl
	    array set IMTOC $IMTOCl
	}

	set R http://[dict get $r host]/4
	return [redir $r $R [<a> href $R "Loaded MOTD"]]
    }

    proc /reloadWELCOME {r} {
	variable WELCOMEchange
	variable docroot
	set wf [file join $docroot html welcome.html]

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
	return [Http Ok $r [<a> href $R "Loaded CSS"] text/html]
    }

    proc /welcome {r} {
	variable TOC
	variable WELCOME
	variable protected

	if {[info exists ::starkit_welcomezero] && $::starkit_welcomezero} {
	    return [Http Redir $r "http://[dict get $r host]/0"]
	}
	
	set menu [menus Recent Help]
	set footer [menus Recent Help Search]

	if {[info exists ::starkit_wikittitle]} {
	    set Title $::starkit_wikittitle
	    set name $::starkit_wikittitle
	} else {
	    set Title "Welcome to the Tclers Wiki!"
	    set name "Welcome to the Tclers Wiki!"
	}

	set updated ""
	set ro ""
	set C $WELCOME
	set T ""

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

    proc timestamp {{t ""}} {
	if {$t == ""} { set t [clock seconds] }
	clock format $t -gmt 1 -format {%Y-%m-%d %T}
    }

    # called to generate a page with references
    proc /ref {r N A} {
	if {[dict get? $r -ua_class] eq "robot"} {
	    return [robot $r]
	}

	if { ![string is integer -strict $A] } {
	    set A 0
	}
	#set N [dict get $r -suffix]
	Debug.wikit {/ref $N}
	if {![string is integer -strict $N]} {
	    return [Http NotFound $r]
	}
	if {$N >= [WDB PageCount]} {
	    return [Http NotFound $r]
	}

	set refList ""
	foreach from [WDB ReferencesTo $N] {
	    lassign [WDB GetPage $from name date who] name date who
	    lappend refList [list [timestamp $date] $name $who $from]
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
	set menu [menus Home Recent Help]
	set footer [menus Home Recent Help Search]

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

    # InfoProc {name} - lookup $name in db,
    # returns a list: /$id (with suffix of @ if the page is new), $name, modification $date
    proc InfoProc {ref} {
	set id [WDB LookupPage $ref]
	lassign [WDB GetPage $id name date] name date
	if {$name eq ""} {
	    set id _/edit?N=$id ;# enter edit mode for missing links
	} else {
	    set id /$id	;# add a leading / which format.tcl will strip
	}
	return [list /$id $name $date]
    }

    proc search {key date} {
	Debug.wikit {search: '$key'}
	set long [regexp {^(.*)\*+$} $key x key]	;# trim trailing *

	# tclLog "SearchResults key <$key> long <$searchLong>"
	set rdate $date
	set result "Searched for \"'''$key'''\" (in page titles"
	if {$long} {
	    append result { and contents}
	}
	append result "):\n\n"
	set max 100
	set count 0
	foreach record [WDB Search $key $long $date $max] {
	    dict with record {}

	    # these are fake pages, don't list them
	    if {$id == 2 || $id == 4 || $id == 5} continue

	    append result "   * [timestamp $date] . . . \[$name\]\n"
	    set rdate $date
	    incr count
	}

	if {$count == 0} {
	    append result "   * '''''No matches found'''''\n"
	    set rdate 0
	} else {
	    append result "   * ''Displayed $count matches''\n"
	    set rdate 0
	}

	return [list $result $rdate $long]
    }

    proc pageXML {N} {
	lassign [WDB GetPage $N name date who] name date who
	set page [WDB GetContent $N]
	set stream [WFormat TextToStream [WDB GetContent $N]]
	lassign [WFormat StreamToHTML $stream / ::WikitWub::InfoProc] parsed - toc backrefs
	return [<page> [subst { 
	    [<name> [armour $name]]
	    [<content> [armour $page]]
	    [<date> [Http Date $date]]
	    [<who> [armour $who]]
	    [<parsed> [armour $parsed]]
	    [<toc> [armour $toc]]
	    [<backrefs> [armour $backrefs]]
	}]]
    }

    proc fromCache {r N ext} {
	variable pagecaching
	if {$pagecaching && $ext eq ""} {
	    variable pagecache
	    set p [$pagecache fetch id $N]
	    if {[dict size $p]} {
		dict with p {
		    dict set r -title $title
		    dict set r -caching Wiki_inserted
		    return [list 1 [Http Ok [Http DCache $r] $content $ct]]
		}
	    }
	}
	return 0
    }

    proc Filter {req term} {}

    variable trailers {@ /_/edit ! /_/ref - /_/diff + /_/history}

    proc do {r} {
	# decompose name
	set term [file tail [dict get $r -path]]
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
	    if {$N == 2} {
		# locate has given up - can't find a page - go to search
		return [Http Redir $r "http://[dict get $r host]/_/search" S [Query decode $term$fancy]]
	    } elseif {$N ne $term} {
		# we really should redirect
		if {[dict get? $r -ua_class] eq "robot"} {
		    # try to make robots always use the canonical form
		    return [Http Moved $r "http://[dict get $r host]/$N"]
		} else {
		    return [Http Redir $r "http://[dict get $r host]/$N"]
		}
	    }
	}

	# term is a simple integer - a page number
	if {$fancy ne ""} {
	    variable trailers
	    # we need to redirect to the appropriate spot
	    set url [dict get $trailers $fancy]/$N
	    return [Http Redir $r "http://[dict get $r host]/$url"]
	}

	Filter $r $N	;# filter out selected pages

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
		    set C [WFormat TextToStream $C]
		    lassign [WFormat StreamToHTML $C / ::WikitWub::InfoProc] C U T BR
		    if { $nqdate } {
			append C [<p> [<a> href "/_/search?S=[armour $term]&F=$nqdate&_charset_=utf-8" "More search results..."]]
		    }
		    if { $long } {
			append C <p> 
			append C [<a> href "/_/search?S=[armour [string trimright $term *]]&_charset_=utf-8" "Repeat search in titles only"]
			append C ", or remove trailing asterisks from the search string to search the titles only.</p>"
		    } else {
			append C <p> 
			append C [<a> href "/_/search?S=[armour $term*]&_charset_=utf-8" "Repeat search in titles and contents"]
			append C ", or append an asterisk to the search string to search the page contents as well as titles.</p>"
		    }
		    set q [string trimright $term *]
		    append q "%20site:" [expr {[info exists ::starkit_url]?"http://$::starkit_url":"http://wiki.tcl.tk"}]
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

		# try cached version
		lassign [fromCache $r $N $ext] cached result
		if {$cached} {
		    return $result
		}
	    }

	    default {

		# simple page - non search term
		if {$N >= [WDB PageCount]} {
		    return [Http NotFound $r]
		}

		# try cached version
		lassign [fromCache $r $N $ext] cached result
		if {$cached} {
		    return $result
		}

		# set up a few standard URLs an strings
		lassign [WDB GetPage $N name date who] name date who
		if {$name eq ""} {
		    puts stderr "Error: $e ($eo)"
		    return [Http NotFound $r]
		}

		# fetch page contents
		set content [WDB GetContent $N]
		switch -- $ext {
		    .txt {
			set C $content
			return [Http NoCache [Http Ok $r $C text/plain]]
		    }
		    .str {
			set C [WFormat TextToStream $content]
			return [Http NoCache [Http Ok $r $C text/plain]]
		    }
		    .code {
			set C [WFormat TextToStream $content 0 0 0]
			set C [WFormat StreamToTcl $name $C]
			return [Http NoCache [Http Ok $r $C text/plain]]
		    }
		    .xml {
			set C "<?xml version='1.0'?>"
			append C \n [pageXML $N]
			return [Http NoCache [Http Ok $r $C text/xml]]
		    }
		    default {
			set C [WFormat TextToStream $content]
			dict set r content-location "http://[Url host $r]/$N"
			lassign [WFormat StreamToHTML $C / ::WikitWub::InfoProc] C U T BR
			foreach {containerid bref} $BR {
			    if {[string length $bref]} {
				set brefpage [WDB LookupPage $bref]
			    } else {
				set brefpage $N
			    }
			    dict lappend r -postload [<script> "getBackRefs($brefpage,'$containerid')"]
			}
			set C [string map [list <<TOC>> $T] $C]
		    }
		}
	    }
	}
	
	Debug.wikit {located: $N}

	# set up backrefs
	set refs {1}
	Debug.wikit {[llength $refs] backrefs to $N}
	switch -- [llength $refs] {
	    0 {
		set backRef ""
		set Refs ""
		set Title [armour $name]
	    }
	    1 {
		set backRef /_/ref?N=$N
		set Refs "[Ref $backRef Reference] - "
		set Title [Ref $backRef $name title "click to see reference to this page"]
	    }
	    default {
		set backRef /_/ref?N=$N
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
		append updated " by [<a> href /[WDB LookupPage $who_nick] $who_nick]"
	    }
	    if {[string length $updated]} {
		variable delta
		append updated " " [<a> class delta href /_/diff?N=$N#diff0 $delta]
	    }
	}

	variable protected

	set menu [menus Home Recent Help]
	set footer [menus Home Recent Help Search]
	if {![info exists protected($N)]} {
	    lappend menu {*}[menus HR]
	    if {!$::roflag} {
		lappend menu [Ref /_/edit?N=$N&A=1 "Add comments"]
		lappend footer [Ref /_/edit?N=$N&A=1 "Add comments"]
		lappend menu [Ref /_/edit?N=$N Edit]
		lappend footer [Ref /_/edit?N=$N Edit]
	    }
	    lappend menu [Ref /_/history?N=$N "History"]
	    lappend menu [Ref /_/summary?N=$N "Edit summary"]
	    lappend menu [Ref $backRef References]
	}

	variable TOC
	variable readonly
	if {$readonly ne ""} {
	    set ro "<it>(Read Only Mode: $readonly)</it>"
	} else {
	    set ro ""
	}

	if {$cacheit} {
	    set result [sendPage [Http CacheableContent $r $date] page DCache]
	    variable pagecaching
	    if {$pagecaching} {
		variable pagecache
		if {[$pagecache exists id $N]} {
		    $pagecache set [$pagecache find id $N] content [dict get $result -content] ct [dict get $result content-type] when [clock milliseconds] title [dict get? $result -title]
		} else {
		    $pagecache append id $N content [dict get $result -content] ct [dict get $result content-type] when [clock milliseconds] title [dict get? $result -title]
		}
	    }
	    return $result
	} else {
	    return [sendPage $r]
	}
    }

    # Site WikitWub-specific defaults
    # These may be overwritten by command line, or by vars.tcl
    variable home [file dirname [info script]]
    variable base ""		;# default place for wiki to live
    variable wikitroot ""	;# where the wikit lives
    variable docroot ""		;# where ancillary docs live
    variable overwrite 0		;# set both to overwrite
    variable reallyreallyoverwrite 0	;# set both to overwrite
    variable wikidb wikit.tkd		;# wikit's Metakit DB name
    variable history history		;# history directory
    variable readonly ""		;# the wiki is not readonly
    variable prime 0			;# we do not wish to prime the wikit
    variable utf8clean 0		;# we do not want utf8 cleansing
    variable upflag ""			;# no URL syncing
    variable roflag 0

    proc init {args} {
	variable {*}$args

	Convert Namespace ::WikitWub	;# add wiki-local conversions

	variable base
	variable wikitroot	;# where the wikit lives
	variable docroot	;# where ancillary docs live

	variable overwrite		;# set both to overwrite
	variable reallyreallyoverwrite	;# set both to overwrite
	variable wikidb
	
	variable home
	if {[info exists ::starkit::topdir]} {
	    # configure for starkit delivery
	    if {$base eq ""} {
		set base [file join $::starkit::topdir lib wikitcl wubwikit]
		# if not otherwise specified, everything lives in the sibling of $::starkit::topdir
	    }
	    if {$wikitroot eq ""} {
		set wikitroot [file join $base data]
	    }
	    if {$docroot eq ""} {
		set docroot [file join $base docroot]
	    }
	} else {
	    if {$base eq ""} {
		set base $home
		# if not otherwise specified, everything lives in this directory
	    }
	    if {$wikitroot eq ""} {
		set wikitroot [file join $base data]
	    }
	    if {$docroot eq ""} {
		set docroot [file join $base docroot]
	    }
	}

	Debug.log {WikitWub base:$base docroot:$docroot wikitroot:$wikitroot}

	set origin [file normalize [file join $home docroot]]	;# all the originals live here

	if {![file exists $docroot]} {
	    # new install. copy the origin docroot to $base
	    catch {file mkdir $wikitroot}
	    file copy $origin [file dirname $docroot]
	    if {![file exists [file join $wikitroot $wikidb]]} {
		# don't overwrite an existing wiki db
		file copy [file join $home doc.sample $wikidb] $wikitroot
	    }
	} elseif {$overwrite
		  && $reallyreallyoverwrite
		  && $docroot ne $origin
	      } {
	    # destructively overwrite the docroot and wikiroot contents with the origin
	    catch {file mkdir $wikitroot}
	    file delete -force $docroot
	    file copy -force $origin [file dirname $docroot]
	    file copy -force [file join $home doc $wikidb] $wikitroot
	} else {
	    # normal start, existing db
	}

	# clean up any symlinks in docroot
	package require functional
	package require fileutil
	foreach file [::fileutil::find $docroot [lambda {file} {
	    return [expr {[file type [file join [pwd] $file]] eq "link"}]
	}]] {
	    set dfile [file join [pwd] $file]
	    file copy [file join $drdir [K [file link $dfile] [file delete $dfile]]] $dfile
	}
	
	# initialize wikit DB
	if {[info exists ::starkit_wikitdbpath]} {
	    set wikitdbpath $::starkit_wikitdbpath
	} else {
	    set wikitdbpath [file join $wikitroot $wikidb]
	}

	WDB WikiDatabase file $wikitdbpath shared 1

	package require utf8
	variable utf8re [::utf8::makeUtf8Regexp]
	variable utf8clean

	# move utf8 regexp into utf8 package
	# utf8 package is loaded by Query
	set ::utf8::utf8re $utf8re

	# set message of the day (if any) to be displayed on /4
	catch {
	    variable motd [::fileutil::cat [file join $docroot motd]]
	}

	# set table of contents (if any) to be displayed on in left column menu
	if {[catch {
	    variable TOC [::fileutil::cat [file join $docroot TOC]]
	    variable IMTOC
	    unset -nocomplain IMTOC
	    if {[string length $TOC]} {
		lassign [WFormat FormatWikiToc $TOC] TOC IMTOCl
		array set IMTOC $IMTOCl
	    }
	} e eo]} {
	    Debug.error {Wiki TOC loading: $e $eo}
	    if {![info exists TOC]} {
		set TOC ""
	    }
	    unset -nocomplain IMTOC
	}

	# set welcome message, if any
	catch {
	    variable WELCOME WELCOME [::fileutil::cat [file join $docroot html welcome.html]]
	}

	catch {[WDB GetContent 9]}

	variable roflag 
	set ::roflag $roflag

	# initialize RSS feeder
	if {0} {
	    WikitRss new \
		[expr {[info exists ::starkit_wikittitle]?$::starkit_wikittitle:"Tcler's Wiki"}] \
		[expr {[info exists ::starkit_url]?"http://$::starkit_url/":"http://wiki.tcl.tk/"}]
	}

	variable pagecaching
	variable pagecache
	if {$pagecaching} {
	    # initialize page cache
	    package require View	;# for page caching
	    [View create pagecache file pagecache.db db pagecache layout {
		id:I	;# page number
		content:S	;# generated content
		ct:S		;# content-type
		title:S		;# page title
		when:L		;# date/time generated
	    }] as pagecache
	}
	proc init {args} {}	;# we can't be called twice
    }

    proc new {args} {
	init {*}$args
	return [Direct new {*}$args namespace ::WikitWub ctype "x-text/wiki"]
    }

    proc create {name args} {
	init {*}$args
	return [Direct create $name {*}$args namespace ::WikitWub ctype "x-text/wiki"]
    }

    namespace export -clear *
    namespace ensemble create -subcommands {}
}

# env handling - copy and remove the C-linked env
# we use ::env to communicate with the old wiki code,
# but the original carries serious performance penalties.
array set _env [array get ::env]; unset ::env
array set ::env [array get _env]; unset _env

# initialize pest preprocessor
proc pest {req} {return 0}	;# default [pest] catcher
catch {source [file join [file dirname [info script]] pest.tcl]}

#### set up appropriate debug levels (negative means off)
Debug setting log 10 error 10 query -10 wikit -10 direct -10 convert -10 cookies -10 socket -10

#### Source local config script (not under version control)
catch {source [file join [file dirname [info script]] local.tcl]} r eo
Debug.log {RESTART: [clock format [clock second]] '$r' ($eo)}

Site start application WikitWub nubs wikit.nub home [file normalize [file dirname [info script]]] ini wikit.ini
