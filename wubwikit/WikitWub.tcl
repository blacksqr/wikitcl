#### Source local setup script (not under version control)
if {[file exists [file join [file dirname [info script]] local_setup.tcl]]} {
    source [file join [file dirname [info script]] local_setup.tcl]
}

package require fileutil
package require struct::queue
package require doctools

lappend auto_path [file dirname [info script]]

#### initialize Wikit
package require Site	;# assume Wub/ is already on the path, or in /usr/lib

package require Sitemap
package require stx
package require stx2html
package require Form

package require WDB_sqlite
#package require WDB_mk
package require WikitRss
package require WFormat

package provide WikitWub 1.0

set API(WikitWub) {
    {A Wub interface to tcl wikit}
    base {place where wiki lives (default: same directory as WikitWub.tcl, or parent of starkit mountpoint)}
    wikitroot {where the wikit lives (default: $base/data)}
    docroot {where ancillary documents live (default: $base/docroot)}
    wikidb {wikit's metakit DB name (default wikit.tkd) - no obvious need to change this.}
    history {history directory}
    readonly {Message which makes the wikit readonly, and explains why.  (default "")}
    motd {message of the day (default "")}
    maxAge {max age of login cookie (default "next month")}
    cookie {name of login cookie (default "wikit_e")}
    language {html natural language (default "en")}
    markup_language {Set markup language to be used. Can be wikit, stx or creole. (default: wikit)}
    empty_template {Set text to be used on first edit of a page.}
    hidereadonly {Hide the readonly message. (default: false)}
    inline_html {Allow inline html in wikit markup. (default: false)}
    doctool2html {Allow <<doctool>> in wikit markup. (default: false)}
    tclnroff2html {Allow <<tclnroff>> in wikit markup. (default: false)}
    include_pages {Allow other wiki pages to be include in a wiki page in wikit markup. (default: false)}
    welcomezero {Use page 0 as welcome page. (default: false)}
    css_prefix {Url prefix for CSS files}
    script_prefix {Url prefix for JS files}
    image_prefix {Url prefix for images}
}

proc ::stx2html::local {what} {
    set id [WDB LookupPage $what]
    if {[info exists ::WikitWub::stx2html_collect_refs] && $::WikitWub::stx2html_collect_refs} {
	lappend  ::WikitWub::stx2html_refs $id
    }
    return [<a> href [file join $::WikitWub::pageURL $id] $what]
}

namespace eval WikitWub {
    variable readonly ""
    variable pagecaching 0
    variable inline_html 0
    variable include_pages 0
    variable markup_language wikit
    variable hidereadonly 0
    variable text_url "wiki.tcl.tk"
    variable empty_template "This is an empty page.\n\nEnter page contents here, upload content using the button above, or click cancel to leave it empty.\n\n<<categories>>Enter Category Here\n"
    variable doctool2html 0
    variable tclnroff2html 0
    variable nroffid 0

    variable perms {}	;# dict of operation -> names, names->passwords
    # perms dict is of the form:
    # op {name password name1 {} name2 {}}
    # name1 password
    # name2 {name3 password ...}

    # search the perms dict for a name and password matching those given
    # the search is rooted at the operation dict entry.

    proc permsrch {userid pass el} {
	variable perms
	upvar 1 looked looked

	if {![dict exists $perms $el]} {return 0}	;# there is no $el

	if {[dict exists $looked $el]} {return 0}	;# already checked $el
	dict set looked $el 1	;# record traversal of $el

	set result 0
	if {[llength [dict get $perms $el]]%2} {
	    # this is a singleton - must be user+password - check it
	    set result [expr {$pass eq [dict get $perms $el]}]
	} else {
	    # $el is a dict.  traverse it looking for a match, or a group to search
	    dict for {n v} [dict get $perms $el] {
		if {$n eq $userid && $v eq $pass} {return 1}
		if {$v eq "" && ![dict exists $looked $n]} {
		    if {[permsrch $userid $pass $n]} {
			set result 1
			break
		    }
		}
	    }
	}
	return $result
    }

    # using HTTP Auth, obtain and check a password, issue a challenge if none match
    proc perms {r op} {
	variable perms
	if {![dict exists $perms $op]} return	;# there are no $op permissions, just permit it.

	Debug.wikit {perms $op [dict get? $perms $op]}
	set userid ""; set pass ""
	lassign [Http Credentials $r] userid pass
	Debug.wikit {perms $op ($userid,$pass)}
	set userid [string trim $userid]	;# filter out evil chars
	set pass [string trim $pass]	;# filter out evil chars

	if {$userid ne "" && $pass ne ""} {
	    set looked {}	;# remember password traversal
	    if {[permsrch $userid $pass $op]} {
		Debug.wikit {perms on '$op' ok}
		return 1
	    }
	}

	# fall through - no passwords matched - challenge the client to provide user,password
	set challenge "Please login to $op"
	set content "Please login to $op"
	Debug.wikit {perms challenge '$op'}
	return -code return -level 1 [Http Unauthorized $r [Http BasicAuth $challenge] $content x-text/html-fragment]
    }

    # sortable - include javascripts and CSS for sortable table.
    proc sortable {r} {
	variable css_prefix
	dict lappend r -headers [<style> media all "@import url([file join $css_prefix sorttable.css]);"]
	return $r
    }
    
    proc <P> {args} {
	puts stderr "<P> $args"
	return [<p> {*}$args]
    }

    variable templates
    variable titles

    proc toolbar_edit_button {action img alt} {
	variable markup_language
	return [format {<button type='button' class='editbutton' onClick='%1$s("editarea", "%4$s");' onmouseout='popUp(event,"tip_%1$s")' onmouseover='popUp(event,"tip_%1$s")'><img src='/%3$s'></button><span id='tip_%1$s' class='tip'>%2$s</span>} $action $alt $img $markup_language]
    }

    # page - format up a page using templates
    proc sendPage {r {tname page} {http {NoCache Ok}}} {
	variable templates
	variable titles
	variable mount
	if {$titles($tname) ne ""} {
	    dict set r -title [uplevel 1 subst [list $titles($tname)]]
	}
	dict set r -content [uplevel 1 subst [list $templates($tname)]][<div> class generated [generated $r]]
	dict set r content-type x-text/wiki

	# run http filters
	foreach pf $http {
	    set r [Http $pf $r]
	}
	return $r
    }

    # record a page template
    proc template {name {title ""} {template ""}} {
	variable templates
	if {$template eq ""} {
	    return $templates($name)
	}
	set templates($name) $template
	variable titles; set titles($name) $title
    }

    template empty {} {
	This is an empty page.

	Enter page contents here or click cancel to leave it empty.
	<<categories>>Enter Category Here
    }
    variable gsearch 1
    # return a search form
    template searchF {} {
	[<form> searchform action [file join $::WikitWub::mount search] {
	    [<text> S id searchtxt onfocus {clearSearch();} onblur {setSearch();} [tclarmour [expr {[info exists query]?$query:"Search in titles"}]]]
	    [<hidden> _charset_ ""]
	}]
	[If {$::WikitWub::gsearch} {
	    [<form> gsearchform method get action [file join $::WikitWub::mount gsearch] {
		[<text> S id googletxt onfocus {clearGoogle();} onblur {setGoogle();} [tclarmour [expr {[info exists query]?$query:"Search in pages"}]]]
		[<hidden> _charset_ ""]
	    }]
	} else {
	    [<form> psearchform action [file join $::WikitWub::mount search] {
		[<text> S id searchtxt onfocus {clearSearch();} onblur {setSearch();} [tclarmour [expr {[info exists query]?$query:"Search in pages and titles"}]]]
		[<hidden> _charset_ ""]
		[<hidden> long 1]
	    }]
	}]
    }

    # Page sent on edit when Wiki is in Read-Only Mode
    template ro {Wiki is currently Read-Only} {
	[<h1> "The Wiki is currently in Maintenance Mode"]
	[<p> "No new edits can be accepted at the moment."]
	[<p> "Reason: $::WikitWub::readonly"]
	[<p> [<a> href [file join $::WikitWub::pageURL $N] "Return to the page you were reading."]]
    }

    template menu {} {
	[<div> id menu_area [<div> id wiki_menu [menuUL $menu]][subst [template searchF]][<div> class navigation [<div> id page_toc [expr {[info exists page_toc]?$page_toc:""}]]][<div> class extra [<div> id wiki_toc $::WikitWub::TOC]]]
    }

    template footer {} {
	[<div> class footer [<p> id footer [variable bullet; join $footer $bullet]]]
    }

    template header {} {
	[<div> class header [subst {
	    [<div> class logo [<a> href / class logo $::WikitWub::text_url]]
	    [<div> id title class title [tclarmour $Title]]
	    [expr {[info exists subtitle]?[<div> id updated class updated $subtitle]:""}]
	}]]
    }

    # standard page decoration
    template page {$name} {
	[<div> class container [subst [template header]][subst {
	    [expr {[info exists ::WikitWub::ro]?$::WikitWub::ro:""}]
	    [<div> id wrapper [<div> id content $C]]
	}][subst [template menu]][subst [template footer]]]
    }

    # system page decoration
    template spage {$name} {
	[<div> class container [subst [template header]][subst {
	    [<div> id wrapper [<div> id content $C]]
	}][subst [template menu]][subst [template footer]]]
    }

    # page sent when constructing a reference page
    template refs {References to $N} {
	[<div> class container [subst {
	    [<div> class header [<h1> "References to [Ref $N]"]]
	    [<div> class wrapper [<div> class content $C]]
	    [<hr> noshade]
	    [<div> class footer [<p> id footer [variable bullet; join $footer $bullet]][subst [template searchF]]]
	}]]
    }

    template qr_creole {} {
	[<div> id helptext [subst {
	    [<br>]
	    [<b> "Editing quick-reference:"] <button type='button' id='hidehelpbutton' onclick='hideEditHelp();'>Hide Help</button>
	    [<br>]
	    <ul>
	    <li>[<b> LINK] to [<b> "\[[<a> href ../6 target _blank {Wiki formatting rules}]\]"] - or to [<b> [<a> href http://here.com/ target _blank "http://here.com/"]].</li>
	    <li>[<b> BULLETS] are lines with an asterisk (*) and a space - the item must be one (wrapped) line</li>
	    <li>[<b> "NUMBERED LISTS"] are lines a hash (#) and a space - the item must be one (wrapped) line</li>
	    <li>[<b> PARAGRAPHS] are split with empty lines</li>
	    <li>[<b> "UNFORMATTED TEXT"] starts with a line containng {{{ and ends with a line containing }}}</li>
	    <li>[<b> HIGHLIGHTS] are indicated by  - use ** for [<b> **bold**], three // for [<b> {//}][<i> italics][<b> {//}].</li>
	    <li>[<b> SECTIONS] can be separated with a horizontal line - insert a line containing just 4 dashes</li>
	    <li>[<b> HEADERS] can be specified with lines containing <b>==Header level 1==</b>, <b>===Header level 2===</b> or <b>====Header level 3====</b></li>
	    <li>[<b> TABLE] rows can be specified as <b><tt>|data|data|data|</tt></b>, a <b>header</b> row as <b><tt>|=header|=header|=header|</tt></b></li>
	    </ul>
	}]]
    }

    template qr_wikit {} {
	[<div> id helptext [subst {
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
	}]]
    }

    template qr_stx {} {
	[<div> id helptext [subst {
	    [<br>]
	    [<b> "Editing quick-reference:"] <button type='button' id='hidehelpbutton' onclick='hideEditHelp();'>Hide Help</button>
	    [<br>]
	    <ul>
	    <li>[<b> LINK] to [<b> "\[[<a> href ../6 target _blank {Wiki formatting rules}]\]"] - or to [<b> [<a> href http://here.com/ target _blank "http://here.com/"]].</li>
	    <li>[<b> BULLETS] are lines with an asterisk (*) and a space - the item must be one (wrapped) line</li>
	    <li>[<b> "NUMBERED LISTS"] are lines a hash (#) and a space - the item must be one (wrapped) line</li>
	    <li>[<b> PARAGRAPHS] are split with empty lines</li>
	    <li>[<b> "UNFORMATTED TEXT"] starts with white space</li>
	    <li>[<b> HIGHLIGHTS] are indicated by groups of single quotes - use two for [<b> ''bold''], three for [<b> {'''}][<i> italics][<b> {'''}].</li>
	    <li>[<b> SECTIONS] can be separated with a horizontal line - insert a line containing just 4 dashes</li>
	    <li>[<b> HEADERS] can be specified with lines containing <b>=Header level 1=</b>, <b>==Header level 2==</b> or <b>===Header level 3===</b></li>
	    <li>[<b> TABLE] rows can be specified as <b><tt>|data|data|data</tt></b>, a <b>header</b> row as <b><tt>|+header|header|header</tt></b></li>
	    </ul>
	}]]
    }

    template edit_toolbar_creole {} {
	[<submit> save class editbutton id savebutton value "Save your changes" onmouseout "popUp(event,'tip_save')" onmouseover "popUp(event,'tip_save')" [<img> src /page_save.png]] [<span> id tip_save class tip Save]

	[<button> preview type button class editbutton id previewbutton onclick "previewPage($N,'creole');" onmouseout "popUp(event,'tip_preview')" onmouseover "popUp(event,'tip_preview')" [<img> src /page_white_magnify.png]] [<span> id tip_preview class tip Preview]

	[<submit> cancel class editbutton id cancelbutton value Cancel onmouseout "popUp(event,'tip_cancel')" onmouseover "popUp(event,'tip_cancel')" [<img> src /cancel.png]] [<span> id tip_cancel class tip Cancel]

	&nbsp; &nbsp; &nbsp;
	[toolbar_edit_button bold            text_bold.png           "Bold"]
	[toolbar_edit_button italic          text_italic.png         "Italic"]
	[toolbar_edit_button heading1        text_heading_1.png      "Heading 1"]
	[toolbar_edit_button heading2        text_heading_2.png      "Heading 2"]
	[toolbar_edit_button heading3        text_heading_3.png      "Heading 3"]
	[toolbar_edit_button hruler          text_horizontalrule.png "Horizontal Rule"]
	[toolbar_edit_button list_bullets    text_list_bullets.png   "List with Bullets"]
	[toolbar_edit_button list_numbers    text_list_numbers.png   "Numbered list"]
	[toolbar_edit_button wiki_link       link.png                "Wiki link"]
	[toolbar_edit_button url_link        world_link.png          "World link"]
	[toolbar_edit_button img_link        photo_link.png          "Image link"]
	[toolbar_edit_button code            script_code.png         "Script"]
	[toolbar_edit_button table           table.png               "Table"]
	&nbsp; &nbsp; &nbsp;

	[<button> helpbutton type button class editbutton id helpbutton onclick "editHelp();" onmouseout "popUp(event,'tip_help')" onmouseover "popUp(event,'tip_help')" [<img> src /help.png]] [<span> id tip_help class tip Help]
    }

    template edit_toolbar_wikit {} {
	<button type='submit' class='editbutton' id='savebutton' name='save' value='Save your changes' onmouseout='popUp(event,"tip_save")' onmouseover='popUp(event,"tip_save")'><img src='/page_save.png'></button><span id='tip_save' class='tip'>Save</span>
	<button type='button' class='editbutton' id='previewbutton' onclick='previewPage($N,"wikit");' onmouseout='popUp(event,"tip_preview")' onmouseover='popUp(event,"tip_preview")'><img src='/page_white_magnify.png'></button><span id='tip_preview' class='tip'>Preview</span>
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

    template edit_toolbar_stx {} {
	<button type='submit' class='editbutton' id='savebutton' name='save' value='Save your changes' onmouseout='popUp(event,"tip_save")' onmouseover='popUp(event,"tip_save")'><img src='/page_save.png'></button><span id='tip_save' class='tip'>Save</span>
	<button type='button' class='editbutton' id='previewbutton' onclick='previewPage($N,"stx");' onmouseout='popUp(event,"tip_preview")' onmouseover='popUp(event,"tip_preview")'><img src='/page_white_magnify.png'></button><span id='tip_preview' class='tip'>Preview</span>
	<button type='submit' class='editbutton' id='cancelbutton' name='cancel' value='Cancel' onmouseout='popUp(event,"tip_cancel")' onmouseover='popUp(event,"tip_cancel")'><img src='/cancel.png'></button><span id='tip_cancel' class='tip'>Cancel</span>
	&nbsp; &nbsp; &nbsp;
	[toolbar_edit_button bold            text_bold.png           "Bold"]
	[toolbar_edit_button italic          text_italic.png         "Italic"]
	[toolbar_edit_button superscript     text_superscript.png    "Super script"]
	[toolbar_edit_button subscript       text_subscript.png      "Sub script"]
	[toolbar_edit_button heading1        text_heading_1.png      "Heading 1"]
	[toolbar_edit_button heading2        text_heading_2.png      "Heading 2"]
	[toolbar_edit_button heading3        text_heading_3.png      "Heading 3"]
	[toolbar_edit_button hruler          text_horizontalrule.png "Horizontal Rule"]
	[toolbar_edit_button list_bullets    text_list_bullets.png   "List with Bullets"]
	[toolbar_edit_button list_numbers    text_list_numbers.png   "Numbered list"]
	[toolbar_edit_button wiki_link       link.png                "Wiki link"]
	[toolbar_edit_button url_link        world_link.png          "World link"]
	[toolbar_edit_button img_link        photo_link.png          "Image link"]
	[toolbar_edit_button code            script_code.png         "Script"]
	[toolbar_edit_button table           table.png               "Table"]
	&nbsp; &nbsp; &nbsp;
	<button type='button' class='editbutton' id='helpbutton' onclick='editHelp();' onmouseout='popUp(event,"tip_help")' onmouseover='popUp(event,"tip_help")'><img src='/help.png'></button><span id='tip_help' class='tip'>Help</span>
    }

    template upload {} {
	[<form> uploadform enctype multipart/form-data method post action [file join $::WikitWub::mount edit/save] {
	    [<label> for C [<submit> upload value 1 Upload]][<file> C title {Upload Content} ""]
	    [<hidden> N $N]
	    [<hidden> O [list [tclarmour $date] [tclarmour $who]]]
	    [<hidden> A 0]
	}]
    }

    # page sent when editing a page
    template edit {Editing [armour $name]} {
	[<div> class edit [subst {
	    [<div> class header [subst {
		[<div> class logo $::WikitWub::text_url]
		[If {$as_comment} {
		    [<div> class title "Comment on [tclarmour [Ref $N]]"]
		}]
		[If {!$as_comment} {
		    [<div> class title "Edit [tclarmour [Ref $N]]"]
		}]
		[If {$as_comment} {
		    [<div> class updated "Enter your comment, then press Save below"]
		}]
		[If {!$as_comment} {
		    [<div> class updated "Make your changes, then press Save below"]
		}]
	    }]]
	    [subst [template upload]]
	    [<div> class editcontents [subst {
		[set disabled [expr {$nick eq ""}]
		 <form> edit method post action [file join $::WikitWub::mount edit/save] {
		     [subst [template qr_$markup_language]]
		     [<div> class previewarea_pre id previewarea_pre ""]
		     [<div> class previewarea id previewarea ""]
		     [<div> class previewarea_post id previewarea_post ""]
		     [<div> class toolbar [subst [template edit_toolbar_$markup_language]]]
		     [<textarea> C id editarea rows 35 cols 72 compact 0 style width:100% [expr {($C eq "")?$::WikitWub::empty_template:[tclarmour $C]}]]
		     [<hidden> O [list [tclarmour $date] [tclarmour $who]]]
		     [<hidden> _charset_ {}]
		     [<hidden> N $N]
		     [<hidden> A $as_comment]
		     <input name='save' type='submit' value='Save your changes'>
		     <input name='cancel' type='submit' value='Cancel'>
		     <button type='button' id='previewbutton' onclick='previewPage($N,"$markup_language");'>Preview</button>
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
	    }]]
	}]]
    }

    # page sent when editing a page
    template edit_binary {Editing [armour $name]} {
	[<div> class edit [subst {
	    [<div> class header [subst {
		[<div> class logo $::WikitWub::text_url]
		[<div> class title "Edit [tclarmour [Ref $N]]"]
		[<div> class updated "Select a file, then press Upload"]
	    }]]
	    [subst [template upload]]
	}]]
    }

    template uneditable {Uneditable} {
	[<p> "Page $N is of type $type which cannot be edited."]
    }

    # page sent to enable login
    template login {login} {
	[<p> "Please choose a nickname that your edit will be identified by."]
	[if {0} {[<p> "You can optionally enter a password that will reserve that nickname for you."]}]
	[<form> login method post action [file join $mount edit/login] {
	    [<fieldset> login title Login {
		[<text> nickname title "Nickname"]
		[<input> name save type submit value "Login" {}]
	    }]
	    [<hidden> R [armour $R]]
	}]
    }

    # page sent on bad upload
    template badtype {bad type} {
	[<h2> "Upload of type '$type' on page $N - [Ref $N $name]"]
	[<p> "[<b> {Your changes have NOT been saved}], because the content your browser sent is of an inappropriate type. Only text and images allowed."]
	[<hr> size 1]
    }

    # page sent when upload changes type
    template badnewtype {bad type} {
	[<h2> "Upload of type '$type' on page $N - [Ref $N $name]"]
	[<p> "[<b> {Your changes have NOT been saved}], because the content your browser sent is of a different type ($otype) than the contents already in the data base ($type)."]
	[<hr> size 1]
    }

    # page sent when a browser sent bad utf8
    template badutf {bad UTF-8} {
	[<h2> "Encoding error on page $N - [Ref $N $name]"]
	[<p> "[<b> {Your changes have NOT been saved}], because the content your browser sent contains bogus characters. At character number $point"]
	[<p> $E]
	[<p> [<i> "Please check your browser."]]
	[<hr> size 1]
	[<p> [<pre> [armour $C]]]
	[<hr> size 1]
    }

    # page sent in response to a search
    template search {} {
	[<form> search method get action [file join $mount search] {
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
	[<p> [<i> "Please restart a new [<a> href [file join $mount edit]?N=$N edit] and merge your version (which is shown in full below.)"]]
	[<p> "Got '$O' expected '$X'"]
	[<hr> size 1]
	[<p> [<pre> [armour $C]]]
	[<hr> size 1]
    }

    variable searchForm [string map {%S $search %M $mount} [<form> search method get action [file join %M search] {
	[<fieldset> sfield title "Construct a new search" {
	    [<legend> "Enter a Search Phrase"]
	    [<text> S title "Append an asterisk (*) to search page contents" [armour %S]]
	    [<checkbox> SC title "search page contents" value 1; set _disabled ""]
	    [<hidden> _charset_]
	}]
    }]]

    variable motd ""
    variable TOC ""
    variable wiki_title	;# leave unset to take default

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

    variable maxAge "next month"	;# maximum age of login cookie
    variable cookie "wikit_e"		;# name of login cookie

    variable htmlhead {<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN" "http://www.w3.org/TR/html4/loose.dtd">}
    variable language "en"	;# language for HTML

    # header sent with each page
    #<meta name='robots' content='index,nofollow' />
    variable head {
	[<link> rel stylesheet href [file join $css_prefix wikit_screen.css] media screen type text/css title "With TOC"]
	[<link> rel "alternate stylesheet" href [file join $css_prefix wikit_screen_notoc.css] media screen type text/css title "Without TOC"]
	[<link> rel stylesheet href [file join $css_prefix wikit_print.css] media print type text/css]
	[<link> rel stylesheet href [file join $css_prefix wikit_handheld.css] media handheld type text/css]
	[<link> rel stylesheet href [file join $css_prefix tooltips.css] type text/css]
	
	[<link> rel alternate type application/rss+xml title RSS href /rss.xml]
	<!--\[if lte IE 6\]>
	[<style> media all "@import '[file join $css_prefix ie6.css]';"]
	<!\[endif\]-->
	<!--\[if gte IE 7\]>
	[<style> media all "@import '[file join $css_prefix ie7.css]';"]
	<!\[endif\]-->
	[<script> [string map [list %JP% $script_prefix] {
	    function init() {
		// quit if this function has already been called
		if (arguments.callee.done) return;
		
		// flag this function so we don't do the same thing twice
		arguments.callee.done = true;
		
		try {
		    if (typeof(creole_content) != "undefined")
		    render_creole_in_id('content', creole_content, creole_transclude, creole_categories);
		}
		catch (e){}

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
	    document.write("<script defer src='%JP%/ie_onload1.JS'><\/script>");
	    /*@end @*/
	    
	    /* for other browsers */
	    window.onload = init;
	}]]
	<meta name="verify-v1" content="89v39Uh9xwxtWiYmK2JcYDszlGjUVT1Tq0QX+7H8AD0=">
    }

    # protected pages - these can't be edited (resp read) by non-admin
    variable protected_pages {ADMIN:Welcome ADMIN:TOC}
    variable rprotected_pages {ADMIN:TOC}
    variable protected {}
    variable rprotected {}

    # html suffix to be sent on every page
    variable htmlsuffix

    # convertor from wiki to html
    proc .x-text/wiki.text/html {rsp} {

	# one-shot - initialize $head
	variable head
	variable script_prefix
	variable css_prefix
	set head [subst $head]

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
		append content $head

		append content </head> \n

		append content <body> \n
		append content $rspcontent
		variable markup_language
		variable htmlsuffix
		append content $htmlsuffix($markup_language)

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
	return [.x-text/wiki.text/html $rsp]
    }

    proc /vars {r args} {
	perms $r admin
	set result {}
	set ns [namespace current]
	foreach n [info vars ${ns}::*] {
	    if {[catch {
		append result [<dt> $n] [<dd> [armour [set $n]]] \n
	    } e eo]} {
		append result [<dt> $n] [<dd> "$e ($eo)"] \n
	    }
	}
	return [Http Ok $r [<dl> $result]]
    }

    proc /cclear {r args} {
	perms $r admin
	Cache clear
	variable mount; variable pageURL
	return [Http Redir $r "http://[dict get $r host][file join $pageURL 4]"]
    }

    proc /cache {r args} {
	perms $r admin
	set C [Html dict2table [Cache::2dict] {-url -stale -hits -unmod -ifmod -when -size}]
	return [Http NoCache [Http Ok [sortable $r] $C x-text/wiki]]
    }

    proc /block {r args} {
	perms $r admin
	set C [Html dict2table [Block blockdict] {-site -when -why}]
	return [Http NoCache [Http Ok [sortable $r] $C x-text/wiki]]
    }

    # generate site map
    proc /sitemap {r args} {
	variable docroot; variable pageURL
	set p http://[Url host $r]/[string trimleft $pageURL /]
	set map {}
	append map [Sitemap location $p "" mtime [file mtime $docroot/html/welcome.html] changefreq weekly] \n
	append map [Sitemap location $p 4 mtime [clock seconds] changefreq always priority 1.0] \n

	foreach record [WDB AllPages] {
	    set id [dict get $record id]
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

	lassign [WDB GetPage $N date type] pcdate type

	if {$type ne "" && ![string match "text/*" $type]} {
	    return 1
	}

	set edate [expr {$pcdate-10*86400}]
	set first 1
	set activity 0.0

	foreach record [WDB Changes $N $edate] {
	    dict with record {
		set changes [WDB ChangeSetSize $N $version]
		set activity [expr {$activity + $changes * $delta / double([clock seconds] - $pcdate)}]
		set pcdate $date
		set first 0
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
	variable pageURL
	if {$who ne "" &&
	    [regexp {^(.+)[,@](.*)} $who - who_nick who_ip]
	    && $who_nick ne ""
	} {
	    set who "[<a> href [file join $pageURL [WDB LookupPage $who_nick]] $who_nick]"
	    if {$ip} {
		append who @[<a> rel nofollow target _blank href http://ip-lookup.net/index.php?ip=$who_ip $who_ip]
	    }
	}
	return $who
    }

    variable menus
    variable bullet " &bull; "

    proc menus { args } {
	variable menus
	variable mount; variable pageURL
	if {![info exists menus(Recent)]} {
	    # Init common menu items
	    set menus(Home)   [<a> href $pageURL Home]
	    set menus(Recent) [<a> href [file join $mount recent] "Recent changes"]
	    set menus(Help)   [<a> href [file join $pageURL Help] "Help"]
	    set menus(HR)     <br>
	    set menus(Search) [<a> href [file join $mount searchp] "Search"]
	    set menus(WhoAmI) [<a> href [file join $mount whoami] "WhoAmI"]/[<a> href [file join $mount logout] "Logout"]
	}
	set m {}
	foreach arg $args {
	    if {[string match "<*" $arg]} {
		lappend m $arg
	    } elseif {$arg ne ""} {
		lappend m $menus($arg)
	    }
	}
	return $m
    }

    proc /cleared { r } {
	perms $r read
	variable detect_robots
	if {$detect_robots && [dict get? $r -ua_class] eq "robot"} {
	    return [robot $r]
	}
	set results ""

	set lastDay 0
	foreach record [WDB Cleared] {
	    dict with record {}

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
	    append link [<a> class delta href history?N=$id history]
	    lappend results [<li> $link]
	}
	if {$lastDay} {
	    lappend results </ul>
	}

	# sendPage vars
	set Title "Cleared pages"
	set name "Cleared pages"
	set menu [menus Home Recent Help WhoAmI]
	set footer [menus Home Recent Help Search]
	set C [join $results "\n"]

	return [sendPage $r spage]
    }

    proc mark_annotate_start {N lineVersion who time} {
	set C "\n>>>>>>a;$N;$lineVersion;$who;"
	append C [clock format $time -format "%Y-%m-%d %T" -gmt true]
	return $C
    }

    proc mark_annotate_end {} {
	return "\n<<<<<<"
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
			append C [mark_annotate_end]
		    }
		    append C [mark_annotate_start $N $lineVersion $who $time]
		    set prevVersion $lineVersion
		}
		append C "\n$line"
	    }
	    if { $prevVersion != -1 } {
		append C [mark_annotate_end]
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

    proc removeNonWikitMarkup { t } {
	set r {}
	set skip 0
	foreach l [split $t \n] {
	    if {$l eq "<<doctool>>" || $l eq "<<inlinehtml>>" || $l eq "<<tclnroff>>"} {
		set skip [expr {!$skip}]
		continue
	    } elseif {!$skip} {
		lappend r $l
	    }
	    
	}
	return [join $r \n]
    }

    # Markup language dependent code

    proc mark_new {N V txt} {
	variable markup_language
	switch -exact -- $markup_language {
	    creole -
	    stx { append C "\n\n----\n\n New in version $V\n\n----\n\n$txt\n\n" }
	    wikit { append C ">>>>>>n;$N;$V;;\n$txt\n<<<<<<\n" }
	}
    }

    proc mark_old {N W txt} {
	variable markup_language
	switch -exact -- $markup_language {
	    creole -
	    stx { append C "\n\n----\n\n Old in version $W\n\n----\n\n$txt\n\n" }
	    wikit { append C ">>>>>>o;$N;$W;;\n$txt\n<<<<<<\n" }
	}
    }

    # Replace local links with numeric external links for creole, 
    # otherwise a link will always go through the search
    proc creole_replace_links {N text} {
	variable pageURL
	variable mount
	regsub {\n\{\{\{} $text \x8E text
	regsub {\}\}\}\n} $text \x8E text
	set rC ""
	set trcld {}
	set trcld_id 0
	set categories {}
	foreach {b fb} [split $text \x8E] {
	    set prev_idx 0
	    foreach {ip0 ip1} [regexp -all -inline -indices {\[\[([^\]]+)\]\]} $b] {
		lassign $ip1 idx0 idx1
		set m1 [string range $b $idx0 $idx1]
		if {[regexp {(https?|ftp|news|mailto|file|irc):[^\s:]\S*} $m1]} {
		    lassign $ip0 idx0 idx1
		    append rC [string range $b $prev_idx $idx1]
		    set prev_idx [expr {$idx1+1}]
		} elseif {$m1 eq ".backrefs"} {
		    lassign $ip0 idx0 idx1
		    append rC [string range $b $prev_idx [expr {$idx0-1}]]
		    append rC "<<<cwtid$trcld_id>>>"
		    lappend trcld "\"/_/ref\"" "\"N=$N&A=1\"" "\"cwtid$trcld_id\"" 0
		    set prev_idx [expr {$idx1+1}]
		    incr trcld_id
		} elseif {[string match ".include *" $m1]} {
		    set ih [string trim [string range $m1 8 end]]
		    if {[string is integer -strict $ih]} {
			set NI $ih
		    } else {
			set NI [WDB PageByName $ih]
		    }
		    lassign $ip0 idx0 idx1
		    append rC [string range $b $prev_idx [expr {$idx0-1}]]
		    if {[llength $NI]} {
			append rC "<<<cwtid$trcld_id>>>"
			lappend trcld "\"/_/included\"" "\"N=$NI\"" "\"cwtid$trcld_id\"" 1
			incr trcld_id		    
		    } else {
			append rc "\[\[.include $ih\]\]"
		    }
		    set prev_idx [expr {$idx1+1}]
		} elseif {[string match ".categories *" $m1]} {
		    lassign $ip0 idx0 idx1
		    append rC [string range $b $prev_idx [expr {$idx0-1}]]
		    set prev_idx [expr {$idx1+1}]		    
		    set catl [split [string trim [string range $m1 12 end]] |]
		    if {[llength $catl]} {
			if {[string length $categories]==0} {
			    append categories "<p></p><hr><div class='centered'><table summary='' class=wikit_table><thead><tr>"
			}
			foreach cat $catl {
			    append categories [<th> [<a> href /[WDB LookupPage $cat] $cat]]
			}
		    }
		} else {
		    lassign $ip0 idx0 idx1
		    set id [WDB LookupPage $m1]
		    if {$id ne ""} {
			lassign [WDB GetPage $id type] type
			if {$type ne "" && ![string match "text/*" $type]} {
			    append rC [string range $b $prev_idx [expr {$idx0-1}]] \{\{ [file join $pageURL $mount image?N=$id]|$m1 \}\}
			} else {
			    append rC [string range $b $prev_idx [expr {$idx0-1}]] \[\[ [file join $pageURL $id]|$m1 \]\]
			}
		    } else {
			append rC [string range $b $prev_idx [expr {$idx0-1}]] \[\[ [file join $pageURL $id]|$m1 \]\]
		    }
		    set prev_idx [expr {$idx1+1}]		    
		}
	    }
	    append rC [string range $b $prev_idx end]
	    if {[string length $fb]} {
		append rC "\n\{\{\{$fb\}\}\}\n"
	    }
	}
	if {[string length $categories]} {
	    append categories "</tr></thead></table></div>"
	}
	return [list $rC $trcld $categories]
    }

    proc translate {N name C ext {preview 0}} {
	variable markup_language
	switch -exact -- $ext {
	    .txt {
		return $C
	    }
	    .str {
		switch -exact -- $markup_language {
		    creole { return $C }
		    stx { return [stx::translate $C] }
		    wikit { return [WFormat TextToStream $C] }
		}
	    }
	    .code {
		switch -exact -- $markup_language {
		    creole -
		    stx { return $C }
		    wikit { return [WFormat StreamToTcl $name [WFormat TextToStream $C 0 0 0]] }
		}
	    }
	    .xml {
		return $C
	    }
	    default {
		switch -exact -- $markup_language {
		    creole {
			lassign [creole_replace_links $N $C] C trcld categories
			if {$preview} {
			    return [list $C]
			} else {
			    set cc [string map {\n \\n ' \\'} $C]
			    set cc [<script> type text/javascript "var creole_content = '$cc';"]
			    append cc [<script> type text/javascript "var creole_transclude = new Array([join $trcld ,]);"]
			    append cc  [<script> type text/javascript "var creole_categories = \"$categories\";"]
			    return [list $cc]
			}
		    }
		    stx { 
			set ::stx2html::local ::WikitWub::stx2html_local
			return [list [stx2html::translate $C]] 
		    }
		    wikit {
			return [WFormat StreamToHTML [WFormat TextToStream $C] / ::WikitWub::InfoProc $preview]
		    }
		}
	    }
	}
    }

    proc summary_diff { N V W {rss 0} } {
	Debug.wikit {summary_diff N:$N V:$V W:$W rss:$rss}
	set t1 [split [removeNonWikitMarkup [get_page_with_version $N $V 0]] \n]
	set W [expr {$V-1}]
	set t2 [split [removeNonWikitMarkup [get_page_with_version $N $W 0]] \n]
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
			append C [mark_new $N $V [lindex $t1 $p1]]
		    }
		    incr p1
		}
		while { $p2 < $i2 } {
		    if {$rss} {
			#			append C ">>>>>>o;$N;$W;;\n[lindex $t2 $p2]\n<<<<<<\n"
		    } else {
			append C [mark_old $N $W [lindex $t2 $p2]]
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
		append C [mark_new $N $V [lindex $t1 $p1]]
	    }
	    incr p1
	}
	while { $p2 < [llength $t2] } {
	    if {$rss} {
		#		append C ">>>>>>o;$N;$V;;\n[lindex $t2 $p2]\n<<<<<<\n"
	    } else {
		append C [mark_old $N $V [lindex $t2 $p2]]
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
	variable detect_robots
	if {$detect_robots && [dict get? $r -ua_class] eq "robot"} {
	    return [robot $r]
	}

	perms $r read
	variable rprotected
	if {[dict exists $rprotected $N]} {
	    perms $r admin
	}

	variable delta
	variable mount

	set N [file rootname $N]	;# it's a simple single page
	if {![string is integer -strict $N] || $N < 0 || $N >= [WDB PageCount]} {
	    return [Http NotFound $r]
	}

	set type [WDB GetPage $N type]

	# For binary pages, show history as summary
	if {$type ne "" && ![string match "text/*" $type]} {
	    return [Http Redir $r [file join $mount history?N=$N]]
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
		lassign [translate $N $name $C .html] C U T BR
		append R $C
		set pcdate $cdate
		set pcwho $cwho
		incr V -1
		if {$V < 1} break
	    }
	}
	append R </ul> \n

	# sendPage vars
	set menu [menus Home Recent Help WhoAmI HR [<a> href [file join $mount history?N=$N] History] [<a> href [file join $mount summary?N=$N] "Edit summary"] [<a> href [file join $mount diff?N=$N] "Last change"] [<a> href [file join $mount diff?N=$N&T=1&D=1] "Changes last day"] [<a> href [file join $mount diff?N=$N&T=1&D=7] "Changes last week"] Search]
	set footer [menus Home Recent Help Search]

	set C $R
	set Title [Ref $N]
	set name "Edit summary for $name"
	set subtitle "Edit summary"

	return [sendPage $r spage]
    }

    proc /diff {r N {V -1} {D -1} {W 0} {T 0}} {
	variable detect_robots
	if {$detect_robots && [dict get? $r -ua_class] eq "robot"} {
	    return [robot $r]
	}

	perms $r read
	variable rprotected
	if {[dict exists $rprotected $N]} {
	    perms $r admin
	}

	# If T is zero, D contains version to compare with
	# If T is non zero, D contains a number of days and /diff must
	Debug.wikit {/diff N:$N V:$V D:$D W:$W T:$T}
	variable mount; variable pageURL
	
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

	set type [WDB GetPage $N type]

	# For binary pages, show history as diff
	if {$type ne "" && ![string match "text/*" $type]} {
	    return [Http Redir $r [file join $mount history?N=$N]]
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
	set subtitle ""
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
		    set subtitle "Changes last day"
		} elseif {$D==7} {
		    set subtitle "Changes last week"
		} else {
		    set subtitle "Changes last $D days"
		}
	    }

	    # get most recent change
	    set dt [expr {$vt-$D*86400}]
	    set D [WDB MostRecentChange $N $dt]
	}

	set name [WDB GetPage $N name]

	set t1 [get_page_with_version $N $V]
	if {!$W} { set t1 [removeNonWikitMarkup $t1] }
	set t1 [split $t1 "\n"]
	if {!$W} { set uwt1 [unWhiteSpace $t1] } else { set uwt1 $t1 }

	set t2 [get_page_with_version $N $D]
	if {!$W} { set t2 [removeNonWikitMarkup $t2] }
	set t2 [split $t2 "\n"]
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
			lassign [WFormat StreamToHTML [WFormat TextToStream $C] $pageURL ::WikitWub::InfoProc] C U T BR
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
	
	set menu [menus Home Recent Help WhoAmI HR [<a> href history?N=$N History] [<a> href summary?N=$N "Edit summary"] [<a> href diff?N=$N "Last change"] [<a> href diff?N=$N&T=1&D=1 "Changes last day"] [<a> href diff?N=$N&T=1&D=7 "Changes last week"]]
	set footer [menus Home Recent Help Search]

	if {![string length $subtitle]} {
	    set subtitle "Difference between version $V and $D"
	}

	return [sendPage $r spage]
    }

    proc /revision {r N {V -1} {A 0}} {
	variable detect_robots
	if {$detect_robots && [dict get? $r -ua_class] eq "robot"} {
	    return [robot $r]
	}

	perms $r read
	variable rprotected
	if {[dict exists $rprotected $N]} {
	    perms $r admin
	}

	Debug.wikit {/revision N=$N V=$V A=$A}

	variable mount
	variable markup_language

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

	set menu [menus Home Recent Help WhoAmI HR [<a> href history?N=$N History]]

	set name [WDB GetPage $N name]
	if {$V >= 0} {
	    set C [get_page_with_version $N $V $A]
	    switch -- $ext {
		.txt -
		.code -
		.str {
		    return [Http NoCache [Http Ok $r [translate $N $name $C $ext] text/plain]]
		}
		default {
		    if {$A} {
			set Title "Annotated version $V of [Ref $N]"
			set name "Annotated version $V of $name"
		    } else {
			set Title "Version $V of [Ref $N]"
			set name "Version $V of $name"
		    }
		    lassign [translate $N $name $C $ext] C U T BR IH DTl TNRl
		    set C [DoctoolPages $r $C $DTl]
		    set C [TclNRoffPages $r $C $TNRl]
		    variable include_pages
		    if {$include_pages} {
			lassign [IncludePages $r $C $IH] r C
		    }
		    if { $V > 0 } {
			lappend menu [<a> href "revision?N=$N&V=[expr {$V-1}]&A=$A" "Previous version"]
		    }
		    if { $V < $nver } {
			lappend menu [<a> href "revision?N=$N&V=[expr {$V+1}]&A=$A" "Next version"]
		    }
		    if {$markup_language eq "wikit"} {
			if { $A } {
			    lappend menu [<a> href "revision?N=$N&V=$V&A=0" "Not annotated"]
			} else {
			    lappend menu [<a> href "revision?N=$N&V=$V&A=1" "Annotated"]
			}
		    }
		}
	    }
	}

	set footer [menus Home Recent Help Search]
	return [sendPage $r spage]
    }

    # /history - revision history
    proc /history {r N {S 0} {L 25}} {
	variable detect_robots
	if {$detect_robots && [dict get? $r -ua_class] eq "robot"} {
	    return [robot $r]
	}

	perms $r read
	variable detect_robots
	if {$detect_robots && [dict get? $r -ua_class] eq "robot"} {
	    return [robot $r]
	}

	Debug.wikit {/history $N $S $L}

	variable mount; variable pageURL
	variable markup_language

	if {![string is integer -strict $N]
	    || ![string is integer -strict $S]
	    || ![string is integer -strict $L]
	    || $N < 0 || $N >= [WDB PageCount]
	    || $S < 0
	    || $L <= 0} {
	    return [Http NotFound $r]
	}

	set C ""
	set menu {}
	if {$S > 0} {
	    set pstart [expr {$S - $L}]
	    if {$pstart < 0} {
		set pstart 0
	    }
	    lappend menu [<a> href "history?N=$N&S=$pstart&L=$L" "Previous $L"]
	}
	set nstart [expr {$S + $L}]
	set nver [WDB Versions $N]
	if {$nstart < $nver} {
	    lappend menu [<a> href "history?N=$N&S=$nstart&L=$L" "Next $L"]
	}

	lassign [WDB GetPage $N name type] name type

	append C "<table summary='' class='history'><thead class='history'>\n<tr>"
	if {$type eq "" || [string match "text/*" $type]} {
	    if {$markup_language eq "wikit"} {
		set histheaders {Rev 1 Date 1 {Modified by} 1 {Line compare} 3 {Word compare} 3 Annotated 1 WikiText 1}
	    } else {
		set histheaders {Rev 1 Date 1 {Modified by} 1 {Word compare} 3 WikiText 1}
	    }
	} else {
	    set histheaders {Rev 1 Date 1 {Modified by} 1 Image 1}
	}
	foreach {column span} $histheaders {
	    append C [<th> class [lindex $column 0] colspan $span $column]
	}
	append C "</tr></thead><tbody>\n"
	if {$type eq "" || [string match "text/*" $type]} {
	    set rowcnt 0
	    set versions [WDB ListPageVersions $N $L $S]
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
		append C [<td> class Rev [<a> href "revision?N=$N&V=$vn" rel nofollow $vn]]
		append C [<td> class Date [clock format $date -format "%Y-%m-%d %T" -gmt 1]]
		append C [<td> class Who [WhoUrl $who]]
		
		if {$markup_language eq "wikit"} {
		    if { $prev >= 0 } {
			append C [<td> class Line1 [<a> href "diff?N=$N&V=$vn&D=$prev#diff0" $prev]]
		    } else {
			append C <td></td>
		    }
		    if { $next <= $nver } {
			append C [<td> class Line2 [<a> href "diff?N=$N&V=$vn&D=$next#diff0" $next]]
		    } else {
			append C <td></td>
		    }
		    if { $vn != $curr } {
			append C [<td> class Line3 [<a> href "diff?N=$N&V=$curr&D=$vn#diff0" Current]]
		    } else {
			append C <td></td>
		    }
		}

		if { $prev >= 0 } {
		    append C [<td> class Word1 [<a> href "diff?N=$N&V=$vn&D=$prev&W=1#diff0" $prev]]
		} else {
		    append C <td></td>
		}
		if { $next <= $nver } {
		    append C [<td> class Word2 [<a> href "diff?N=$N&V=$vn&D=$next&W=1#diff0" $next]]
		} else {
		    append C <td></td>
		}
		if { $vn != $curr } {
		    append C [<td> class Word3 [<a> href "diff?N=$N&V=$curr&D=$vn&W=1#diff0" Current]]
		} else {
		    append C <td></td>
		}
		
		if {$markup_language eq "wikit"} {
		    append C [<td> class Annotated [<a> href "revision?N=$N&V=$vn&A=1" $vn]]
		}
		append C [<td> class WikiText [<a> href "revision?N=$N.txt&V=$vn" $vn]]
		append C </tr> \n
		incr rowcnt
	    }
	} else {
	    set rowcnt 0
	    set versions [WDB ListPageVersionsBinary $N $L $S]
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
		append C [<td> class Rev $vn]
		append C [<td> class Date [clock format $date -format "%Y-%m-%d %T" -gmt 1]]
		append C [<td> class Who [WhoUrl $who]]
		append C [<td> class Image [<img> src [file join $pageURL $mount image?N=$N&V=$vn]]]
		append C </tr> \n
		incr rowcnt
	    }
	}
	append C </tbody></table> \n

	# sendPage vars
	set name "Change history of [WDB GetPage $N name]"
	set Title "Change history of [Ref $N]"
	set footer [menus Home Recent Help Search]
	set menu [menus Home Recent Help WhoAmI HR {*}$menu]

	return [sendPage $r spage]
    }

    # Ref - utility proc to generate an <A> from a page id
    proc Ref {url {name "" } args} {
	variable pageURL
	if {$name eq ""} {
	    set page [lindex [file split $url] end]
	    set name [WDB GetPage $page name]
	    if {$name eq ""} {
		set name $page
	    }
	}
	return [<a> href [file join $pageURL $url] {*}$args [armour $name]]
    }

    set redir {meta: http-equiv='refresh' content='10;url=$url'

	<h1>Redirecting to $url</h1>
	<p>$content</p>
    }

    proc redir {r url content} {
	variable redir
	return [Http NoCache [Http Found $r $url [subst $redir]]]
    }

    proc /who {r} {
	set C [Html dict2table [dict get $r -session] {who edit}]
	return [Http NoCache [Http Ok [sortable $r] $C x-text/wiki]]
    }

    proc /whoami {r} {
	variable pageURL
	set nick [who $r]
	if {[string length $nick]} {
	    set C "You are '[<a> href [file join $pageURL $nick] $nick]'."
	} else {
	    set C "You are not logged in. Login is required to edit a page. You will be asked to provided a user-name the next time you edit a page."
	}

	# sendPage vars
	set name "Who Am I?"
	set Title "Who Am I?"
	set menu [menus Home Recent Help WhoAmI]
	set footer [menus Home Recent Help Search]
	return [sendPage $r spage]
    }

    proc /logout {r} {
	variable mount
	variable cookie
	set r [Cookies Clear $r path $mount -name $cookie]
	if {[dict exists $r referer]} {
	    return [Http Redir $r [dict get $r referer]]	
	} else {
	    return [/whoami $r]
	}
    }

    proc /edit/login {r {nickname ""} {R ""}} {
	perms $r write
	variable mount
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

	set dom [dict get $r -host]

	# include an optional expiry age
	variable maxAge
	if {$maxAge ne ""} {
	    set age [list -expires $maxAge]
	} else {
	    set age {}
	}

	variable cookie
	variable mount
	Debug.wikit {/login - created cookie $nickname with R $R}
	set r [Cookies Add $r -path $mount -name $cookie -value $nickname {*}$age]

	if {$R eq ""} {
	    set R [Http Referer $r]
	    if {$R eq ""} {
		set R "http://[dict get $r host]/"
	    }
	}

	return [redir $r $R [<a> href $R "Created Account"]]
    }

    proc invalidate {r url} {
	dict set r -path [string trimright $url /]
	set urln [Url url $r]
	Debug.wikit {invalidating $url->$urln} 3
	return [Cache delete $urln]
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
	return -1	;# the search page
    }

    proc /gsearch {r {S ""}} {
	perms $r read

	set subtitle "powered by <img class='branding' src='http://www.google.com/uds/css/small-logo.png'</img>"
	set C [<script> src "http://www.google.com/jsapi?key=$::google_jsapi_key"]
	append C \n
	append C [<script> {google.load('search', '1');}]
	append C \n

	# sendPage vars
	variable query $S
	set name "Search"
	set Title "Search"
	set menu [menus Home Recent Help WhoAmI]
	set footer [menus Home Recent Help]

	return [sendPage $r spage]
    }

    proc who {r} {
	variable cookie
	set cl [Cookies Match $r -name $cookie]
	if {[llength $cl] != 1} {
	    return ""
	} else {
	    Debug.wikit {who /edit/ $cl}
	    return [dict get [Cookies Fetch $r -name $cookie] -value]
	}
    }

    proc /preview { r N O } {
	variable detect_robots
	if {$detect_robots && [dict get? $r -ua_class] eq "robot"} {
	    return [robot $r]
	}

	perms $r read
	variable rprotected
	if {[dict exists $rprotected $N]} {
	    perms $r admin
	}

	set O [string map {\t "        "} [encoding convertfrom utf-8 $O]]
	lassign [translate $N preview $O .html 1] C U T BR
	set C [string map [list "<<TOC>>" [<p> [<b> [<i> "Table of contents will be inserted here."]]]] $C]

	return [Http NoCache [Http Ok $r [tclarmour $C] text/plain]]
    }

    proc /included { r N } {
	variable detect_robots
	variable pageURL
	variable mount
	if {$detect_robots && [dict get? $r -ua_class] eq "robot"} {
	    return [robot $r]
	}

	perms $r read
	variable rprotected
	if {[dict exists $rprotected $N]} {
	    perms $r admin
	}

	lassign [WDB GetPage $N type] type
	if {$type ne "" && ![string match text/* $type]} {
	    set U {}
	    set T {}
	    set BR {}
	    set C [<img> src [file join $pageURL $mount image?N=$N]]
	} else {
	    set O [WDB GetContent $N]
	    lassign [translate $N preview $O .html 1] C U T BR
	    set C [string map [list "<<TOC>>" [<p> [<b> [<i> "Table of contents will be inserted here."]]]] $C]
	}
	return [Http NoCache [Http Ok $r [tclarmour $C] text/plain]]
    }

    proc /image { r N {V -1} } {
	variable detect_robots
	variable pageURL
	if {$detect_robots && [dict get? $r -ua_class] eq "robot"} {
	    return [robot $r]
	}

	perms $r read
	variable rprotected
	if {[dict exists $rprotected $N]} {
	    perms $r admin
	}

	lassign [WDB GetPage $N type] type
	if {$type ne "" && ![string match text/* $type]} {
	    if {[string is integer -strict $V] && $V >= 0} {
		lassign [WDB GetBinary $N $V] C type
		return [Http Ok $r $C $type]
	    } else {
		lassign [WDB GetBinary $N -1] C type
		return [Http Ok $r $C $type]
	    }
	} else {
	    return [Http NotFound $r]
	}
    }

    proc /edit/save {r N C O A save cancel preview upload} {
	perms $r write
	variable mount
	variable pageURL

	Debug.wikit {/edit/save N:$N A:$A O:$O preview:$preview save:$save cancel:$cancel upload:$upload}
	Debug.wikit {Query: [dict get $r -Query] / [dict get $r -entity]}

	variable detect_robots
	if {$detect_robots && [dict get? $r -ua_class] eq "robot"} {
	    return [robot $r]
	}

	if { [string tolower $cancel] eq "cancel" } {
	    set url http://[Url host $r][file join $pageURL $N]
	    return [redir $r $url [<a> href $url "Canceled page edit"]]
	}

	variable readonly
	if {$readonly ne ""} {
	    Debug.wikit {/edit/save failed wiki is readonly}
	    return [sendPage $r ro]
	}

	if {![string is integer -strict $N]} {
	    Debug.wikit {/edit/save failed can only save to page by number}
	    return [Http NotFound $r]
	}

	if {$N < 0 || $N >= [WDB PageCount]} {
	    Debug.wikit {/edit/save failed page out of range}
	    return [Http NotFound $r]
	}

	lassign [WDB GetPage $N name date who type ] name date who otype
	set page [WDB GetContent $N]
	if {$name eq ""} {
	    Debug.wikit {/edit/save failed $N is not a valid page}
	    return [Http NotFound $er [subst {
		[<h2> "$N is not a valid page."]
		[<p> "[armour $r]([armour $eo])"]
	    }]]
	}

	# is the caller logged in?
	set nick [who $r]
	set when [expr {[dict get $r -received] / 1000000}]

	Debug.wikit {/edit/save N:$N C?:[expr {$C ne ""}] who:$nick when:$when - modified:"$date $who" O:$O }

	# if there is new page content, save it now
	set url http://[Url host $r][file join $pageURL $N]
	if {$N eq "" || $C eq ""} {
	    return [Http NoCache [Http SeeOther $r $url [subst $redir]]]
	    #return [redir $r $url [<a> href $url "Edited Page"]]
	}

	variable protected
	if {[dict exists $protected $N]} {
	    perms $r admin
	    Debug.wikit {/edit/save protected page OK}
	}

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
	
	# if upload, check mime type
	if {$upload ne ""} {
	    set type [Mime magic $C]
	    Debug.wikit "Mime magic: $type"
	    if {$type eq ""} {
		# we don't know what type - assume wiki text
		set type text/x-wikit
	    } elseif {![string match image/* $type]
		&& [string match text/* $type]
	    } {
		Debug.wikit "Bad Type: $type"
		return [sendPage $r badtype]
	    }
	} else {
	    # editing without upload can only create wiki pages
	    set type text/x-wikit
	}

	# type must be text/* or image/*
	if {![string match text/* $type] && ![string match image/* $type]} {
	    return [sendPage $r badtype]
	}
	
	# text must stay text
	if {$otype ne "" && [string match text/* $otype] && ![string match text/* $type]} {
	    return [sendPage $r badnewtype]	    
	}

	# permit filtering of uploads of given type by means of password
	perms $r [lindex [string trim $type /] 0]

	if {[string match text/* $type]} {
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

	    # save the page into the db.
	    if {[string is integer -strict $A] && $A} {
		# Look for category at end of page using following styles:
		# ----\n[Category ...]
		# ----\n!!!!!!\n%|Category...|%\n!!!!!!
		set Cl [split [string trimright [WDB GetContent $N] \n] \n]
		if {[string trim [lindex $Cl end]] eq "!!!!!!" && 
		    [string trim [lindex $Cl end-2]] eq "!!!!!!" && 
		    [string match "----*" [string trim [lindex $Cl end-3]]] && 
		    [string match "%|*Category*|%" [string trim [lindex $Cl end-1]]]} {
		    set Cl [linsert $Cl end-4 ---- "'''\[$nick\] - [clock format [clock seconds] -format {%Y-%m-%d %T}]'''" {} $C {}]
		} elseif {[string match "<<categories>>*" [lindex $Cl end]]} {
		    set Cl [linsert $Cl end-1 ---- "'''\[$nick\] - [clock format [clock seconds] -format {%Y-%m-%d %T}]'''" {} $C {}]
		} else {
		    variable markup_language
		    switch -- $markup_language {
			creole { set nn "\[\[$nick\]\]" }
			default { set nn "\[$nick\]" }
		    }
		    lappend Cl ---- "'''$nn - [clock format [clock seconds] -format {%Y-%m-%d %T}]'''" {} $C
		}
		set C [join $Cl \n]
	    }
	    set C [string map {\t "        " "Robert Abitbol" unperson RobertAbitbol unperson Abitbol unperson} $C]
	} else {
	    # check that person is allowed to upload type they've sent
	}

	if {$C eq [WDB GetContent $N]} {
	    Debug.wikit {/edit/save failed: No change, not saving  $N}
	    return [redir $r $url [<a> href $url "Unchanged Page"]]
	}

	Debug.wikit {/edit/save SAVING $N of type:'$type'}
	if {[catch {
	    set who $nick@[dict get $r -ipaddr]
	    WDB SavePage $N $C $who $name $type $when
	} err eo]} {
	    set readonly $err
	    invalidate $r [file join $pageURL $N]
	    invalidate $r [file join $mount recent]
	}

	variable pagecaching
	if {$pagecaching} {
	    Debug.wikit {/edit/save clearing pagecache for $N and 4}
	    if {[WDB pagecache exists $N]} {
		WDB pagecache delete $N
	    }
	    if {[WDB pagecache exists recent]} {
		WDB pagecache delete recent
	    }
	}

	# give effect to editing of TOC
	variable protected
	if {$N == [dict get? $protected ADMIN:TOC]} {
	    reloadTOC
	}

	# Only actually save the page if the user selected "save"
	invalidate $r [file join $pageURL $N]
	invalidate $r [file join $mount recent]
	invalidate $r [file join $mount ref]/$N
	invalidate $r /_/rss.xml; WikitRss clear
	invalidate $r [file join $mount summary]/$N

	# if this page did not exist before:
	# remove all referencing pages.
	#
	# this makes sure that cache entries point to a filled-in page
	# from now on, instead of a "[...]" link to a first-time edit page
	variable include_pages
	if {$date == 0 || $include_pages} {
	    foreach from [WDB ReferencesTo $N] {
		invalidate $r [file join $pageURL $from]
	    }
	}

	Debug.wikit {/edit/save complete $N}
	# instead of redirecting, return the generated page with a Content-Location tag
	#return [do $r $N]
	return [redir $r $url [<a> href $url "Edited Page"]]
    }

    proc /revert_last_edit {r N} {
	perms $r admin
	if {![string is integer -strict $N]} {
	    return [Http NotFound $r]
	}

	variable protected
	if {[dict exists $protected $N]} {
	    return [Http Ok $r "Protected pages can not be delete." text/html]
	}

	if {$N < 0 || $N >= [WDB PageCount]} {
	    return [Http NotFound $r]
	}
	
	lassign [WDB GetPage $N type] type

	if {$type ne "" && ![string match "text/*" $type]} {
	    set last_version [expr {[WDB VersionsBinary $N] -1}]
	    if {$last_version > 0} {
		set C [get_page_with_version $N $last_version 0]
		WDB Revert $N $last_version $C 
	    }
	} else {
	    set last_version [expr {[WDB Versions $N] - 1}]
	    if {$last_version > 0} {
		WDB RevertBinary $N $last_version
	    }
	}
    }

    proc /delete {r N} {
	perms $r admin
	if {![string is integer -strict $N]} {
	    return [Http NotFound $r]
	}

	variable protected
	if {[dict exists $protected $N]} {
	    return [Http Ok $r "Protected pages can not be delete." text/html]
	}

	if {$N < 0 || $N >= [WDB PageCount]} {
	    return [Http NotFound $r]
	}
	
	if {[llength [WDB ReferencesTo $N]]} {
	    variable mount
	    return [Http Ok $r "References to page $N still exist, page can not be delete. List of pages referencing this page can be found <a href='[file join $mount ref]?N=$N'>here</a>" text/html]
	}
	
	WDB Delete $N

	return [Http Ok $r "Page $N deleted." text/html]
    }

    proc /map {r imp args} {
	perms $r read
	variable protected
	variable IMTOC
	variable pageURL
	if {[info exists IMTOC($imp)]} {
	    return [Http Redir $r "http://[dict get $r host]/[string trim $::WikitWub::IMTOC($imp) /]"]
	} else {
	    set TOCp [dict get? $protected ADMIN:TOC]
	    if {$TOCp ne ""} {
		return [Http Redir $r [file join $pageURL $TOCp]]
	    } else {
		return [Http NotFound $r [<p> "ADMIN:TOC does not exist."]]
	    }

	}
    }

    # /reload - direct url to reload numbered pages from fs
    proc /reload {r} {
	foreach {} {}
    }

    # called to generate an edit page
    proc /edit {r N A args} {
	Debug.wikit {edit N:$N A:$A ($args)}

	variable mount
	variable pageURL
	variable detect_robots
	variable markup_language
	if {$detect_robots && [dict get? $r -ua_class] eq "robot"} {
	    return [robot $r]
	}
	perms $r write

	variable readonly
	if {$readonly ne ""} {
	    return [sendPage $r ro]
	}

	if {![string is integer -strict $N]} {
	    return [Http NotFound $r]
	}

	variable protected
	if {[dict exists $protected $N]} {
	    perms $r admin
	}

	if {$N < 0 || $N >= [WDB PageCount]} {
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

	lassign [WDB GetPage $N name date who type] name date who type;# get the last change author

#	if {$type ne "" && ![string match text/* $type]} {
#	    return [sendPage $r uneditable]
#	}

	set who_nick ""
	regexp {^(.+)[,@]} $who - who_nick
	variable as_comment 0
	if {[string is integer -strict $A] && $A} {
	    set as_comment 1
	    set C [armour "<enter your comment here and a header with your wiki nickname and timestamp will be inserted for you>"]
	} else {
	    set C [armour [WDB GetContent $N]]
	}

	if {$type ne "" && ![string match text/* $type]} {
	    return [sendPage $r edit_binary]
	} else {
	    return [sendPage $r edit]
	}
    }

    proc /motd {r} {
	perms $r read
	variable motd
	variable docroot
	variable mount

	puts "\n\n\n\n\nmotd: [file join $docroot motd]\n\n\n\n\n"

	catch {set motd [::fileutil::cat [file join $docroot motd]]}
	set motd [string trim $motd]

	invalidate $r [file join $mount recent]

	set R [Http Referer $r]
	if {$R eq ""} {
	    set R [file join http://[dict get $r host] $mount recent]
	}
	return [redir $r $R [<a> href $R "Loaded MOTD"]]
    }

    proc reloadTOC {} {
	variable mount
	variable pageURL
	variable protected
	variable TOC
	variable IMTOC
	set TOCp [dict get? $protected ADMIN:TOC]
	if {$TOCp ne ""} {
	    if {[catch {
		set TOC [string trim [WDB GetContent $TOCp]]
		unset -nocomplain IMTOC
		
		if {[string length $TOC]} {
		    lassign [WFormat FormatWikiToc $TOC $pageURL] TOC IMTOCl
		    array set IMTOC $IMTOCl
		}
	    } e eo]} {
		set TOC ""
		unset -nocomplain IMTOC
		Debug.error {Wikit Loading TOC: $e ($eo)}
	    }
	} else {
	    set TOC ""
	}
    }

    proc /reloadCSS {r} {
	perms $r admin
	invalidate $r wikit.css
	invalidate $r ie6.css
	set R [dict get $r -url]
	return [Http Ok $r [<a> href $R "Loaded CSS"] text/html]
    }

    proc /welcome {r} {
	perms $r read

	variable TOC
	variable wiki_title
	variable protected
	variable mount
	variable pageURL
	variable welcomezero

	if {[info exists welcomezero] && $welcomezero} {
	    return [Http Redir $r "http://[dict get $r host]/0"]
	}

	if {[info exists wiki_title] && $wiki_title ne ""} {
	    set Title $wiki_title
	    set name $wiki_title
	} else {
	    set Title "Welcome to the Tclers Wiki!"
	    set name "Welcome to the Tclers Wiki!"
	}

	set N [dict get? $protected ADMIN:Welcome]
	set C [string trim [WDB GetContent $N]]
	append C \n [string map [list %P% $N] {<!-- From Page %P% -->}] \n

	if {$C eq ""} {
	    set menu [menus Recent Help WhoAmI]
	    lappend menu [<a> href [file join $mount edit]?N=$N "Create Page"]
	} else {
	    set menu [menus Recent Help WhoAmI]
	}
	set footer [menus Recent Help Search]

	Debug.wikit {/welcome: $N}
	return [sendPage $r spage]
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
	return [clock format $t -gmt 1 -format {%Y-%m-%d %T}]
    }

    # called to generate a page with references
    proc /ref {r N A} {
	variable detect_robots
	if {$detect_robots && [dict get? $r -ua_class] eq "robot"} {
	    return [robot $r]
	}

	perms $r read
	variable rprotected
	if {[dict exists $rprotected $N]} {
	    perms $r admin
	}

	if { ![string is integer -strict $A] } {
	    set A 0
	}
	#set N [dict get $r -suffix]
	Debug.wikit {/ref $N}
	if {![string is integer -strict $N]} {
	    return [Http NotFound $r]
	}
	if {$N < 0 || $N >= [WDB PageCount]} {
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

	# sendPage vars
	set menu [menus Home Recent Help WhoAmI]
	set footer [menus Home Recent Help Search]

	set name "References to $N"
	set Title "References to [Ref $N]"

	if {$A} {
	    return [Http NoCache [Http Ok $r [tclarmour $C] text/plain]]
	} else {
	    return [sendPage $r spage]
	}
    }

    proc GetRefs {text} {
	variable markup_language
	switch -exact -- $markup_language {
	    wikit {
		return [WFormat StreamToRefs [WFormat TextToStream $text] ::WikitWub::InfoProc]
	    }
	    stx {
		variable stx2html_refs {}
		variable stx2html_collect_refs 1
		stx2html::translate -1 $text
		variable stx2html_collect_refs 0
		return $stx2html_refs
	    }
	    creole {
		regsub {\n\{\{\{} $text \x8E text
		regsub {\}\}\}\n} $text \x8E text
		set refs {}
		foreach {b -} [split $text \x8E] {
		    foreach {m0 m1} [regexp -all -inline {\[\[([^\]]+)\]\]} $b] {
			if {![regexp {(https?|ftp|news|mailto|file|irc):[^\s:]\S*} $m1]} {
			    lappend refs [WDB LookupPage $m1]
			}
		    }
		}
		return [lsort -integer -unique $refs]
	    }
	}
    }

    # InfoProc {name} - lookup $name in db,
    # returns a list: /$id (with suffix of @ if the page is new), $name, modification $date
    proc InfoProc {ref {query_only 0}} {
	variable pageURL
	variable mount
	set id [WDB LookupPage $ref $query_only]
	if {$query_only} {
	    return $id
	}
	lassign [WDB GetPage $id name date type] name date type
	if {$name eq ""} {
	    set idlink [file join $mount edit?N=$id] ;# enter edit mode for missing links
	} else {
	    if {$type ne "" && ![string match "text/*" $type]} {
		set idlink [file join $mount image?N=$id]
		set plink $id
	    } else {
		set idlink $id
		set plink $id
	    }
	}
	return [list $id $name $date $type [file join $pageURL $idlink] [file join $pageURL $plink]]
    }

    proc pageXML {N} {
	lassign [WDB GetPage $N name date who] name date who
	set page [WDB GetContent $N]
	lassign [translate $N $name $page .html] parsed - toc backrefs
	return [<page> [subst { 
	    [<name> [xmlarmour $name]]
	    [<content> [xmlarmour $page]]
	    [<parsed> [xmlarmour $parsed]]
	    [<date> [Http Date $date]]
	    [<who> [xmlarmour $who]]
	    [<toc> [xmlarmour $toc]]
	    [<backrefs> [xmlarmour $backrefs]]
	}]]
    }

    proc fromCache {r N {ext ""}} {
	variable pagecaching
	if {$pagecaching && $ext eq "" && [WDB pagecache exists $N]} {
	    set p [WDB pagecache fetch $N]
	    dict with p {
		dict set r -title $title
		dict set r -caching Wiki_inserted
		return [list 1 [Http Ok [Http DCache $r] $content $ct]]
	    }
	}
	return 0
    }

    proc Filter {req term} {}

    proc IncludePages {r C IH} {
	set cnt 0
	foreach ih $IH {
	    if {[string is integer -strict $ih]} {
		set N $ih
	    } else {
		set N [WDB PageByName $ih]
		if {[llength $N]==0} {
		    continue
		}
	    }
	    #	    set ihcontent [WDB GetContent $N]
	    #	    set IHC [WFormat TextToStream $ihcontent]
	    #	    lassign [WFormat StreamToHTML $IHC / ::WikitWub::InfoProc 1] IHC
	    #	    set IHC [string trim $IHC \n]
	    #	    if {[string match "<p></p>*" $IHC]} {
	    #		set IHC [string range $IHC 7 end]
	    #	    }
	    dict lappend r -postload [<script> "getIncluded($N,'included$cnt');"]
	    set idx [string first "@@@@@@@@@@$ih@@@@@@@@@@" $C]
	    set tC [string range $C 0 [expr {$idx-1}]]
	    append tC "<span id='included$cnt'></span>"
	    append tC [string range $C [expr {$idx+20+[string length $ih]}] end]
	    set C $tC
	    incr cnt
	}
	return [list $r $C]
    }

    proc DoctoolPages {r C DTl} {
	foreach {dtid DT} $DTl {
	    doctools::new dt -format html
	    set DT [dt format $DT]
	    dt destroy
	    set bidx [string first "<body>" $DT]
	    set eidx [string first "</body>" $DT]
	    set DT [string range $DT [expr {$bidx+6}] [expr {$eidx-1}]]
	    set C [string map [list "@@@@@@@@@@DT$dtid@@@@@@@@@@" $DT] $C]
	}
	return $C
    }

    proc NRoff2Html {TNR} {
	variable nroffid
	set cnroffid [incr nroffid]
	puts "chan names 1: [chan names]"
	if {[catch {
	    file mkdir /tmp/nroff$cnroffid
	    set f [open /tmp/nroff$cnroffid/tnr.n w]
	    puts $f $TNR
	    close $f
	    set ip [interp create]
	    $ip eval {set argv {}}
	    $ip eval [list set nroffsubdir /tmp/nroff$cnroffid]
	    if {[catch {$ip eval source [file join [file dirname [info script]] tcltk-man2html.tcl]} msg]} {
		set CTNR [armour $msg]
	    } else {
		set CTNR [::fileutil::cat [file join /tmp/nroff$cnroffid/Nroff2Wiki/tnr.htm]]
	    }
	    interp delete $ip
	    file delete -force /tmp/nroff$cnroffid
	} msg]} {
	    set CTNR [armour $CTNR]
	}
	puts "chan names 2: [chan names]"
	return $CTNR
    }

    proc TclNRoffPages {r C TNRl} {
	variable nroffid
	variable tclnroff2html
	if {$tclnroff2html} {
	    foreach {tnrid TNR} $TNRl {
		set C [string map [list "@@@@@@@@@@TNR$tnrid@@@@@@@@@@" [NRoff2Html $TNR]] $C]
	    }
	}
	return $C
    }

    variable trailers {@ _/edit ! _/ref - _/diff + _/history}

    proc generated { r } {
	set genmsg "Generated in [expr {int([clock microseconds] - [dict get $r -received])/1000}]ms"
	if {[dict exist $r -caching]} {
	    append genmsg " " [dict get $r -caching]
	}
	return $genmsg
    }

    # Special page: Recent Changes.
    variable delta [subst \u0394]
    variable delta [subst \u25B2]
    proc /recent {r} {
	# try cached version
	lassign [fromCache $r recent] cached result
	if {$cached} {
	    return $result
	}

	variable rprotected
	variable mount
	variable pageURL
	variable delta
	variable motd

	set C $motd	;# contents includes motd
	set results {}
	set result {}
	set lastDay 0
	set threshold [expr {[clock seconds] - 7 * 86400}]
	set deletesAdded 0
	set activityHeaderAdded 0

	foreach record [WDB RecentChanges $threshold] {
	    dict with record {}

	    # these are fake pages, don't list them
	    if {[dict exists $rprotected $id]} continue

	    # only report last change to a page on each day
	    set day [expr {$date/86400}]

	    # insert a header for each new date
	    if {$day != $lastDay} {

		if { [llength $result] } {
		    lappend results [list2plaintable $result {rc1 rc2 rc3} rctable]
		    set result {}

		    if { !$deletesAdded } {
			lappend results [<p> [<a> class cleared href [file join $mount cleared] "Cleared pages (title and/or page)"]]
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
	    set rtype ""
	    if {[string length $type] && ![string match "text/*" $type]} {
		set rtype [<span> class day " [lindex [split $type /] 0]"]
	    }
	    lappend result [list "[<a> href [file join $pageURL $id] [armour $name]]$rtype [<a> class delta rel nofollow href [file join $mount diff]?N=$id#diff0 $delta]" [WhoUrl $who] [<div> class activity [<a> class activity rel nofollow href [file join $mount summary]?N=$id [string repeat $actimg [edit_activity $id]]]]]
	}

	if { [llength $result] } {
	    lappend results [list2plaintable $result {rc1 rc2 rc3} rctable]
	    if { !$deletesAdded } {
		lappend results [<p> [<a> class cleared href [file join $mount cleared] "Cleared pages (title and/or page)"]]
	    }
	}

	lappend results [<p> "generated [clock format [clock seconds]]"]
	append C \n [join $results \n]

	# sendPage vars
	set name "Recent Changes"
	set Title "Recent Changes"
	set menu [menus Home Recent Help WhoAmI]
	set footer [menus Home Recent Help Search WhoAmI]

	return [sendPage $r spage]
    }

    proc search {key date} {
	Debug.wikit {search: '$key'}
	set long [regexp {^(.*)\*+$} $key x key]	;# trim trailing *

	# tclLog "SearchResults key <$key> long <$searchLong>"
	set rdate $date
	set result "Searched for \"[<b> $key]\" (in page titles"

	if {$long} {
	    append result " and contents"
	}
	append result "):<br>\n"
	set max 100
	set count 0
	variable protected
	variable mount
	variable pageURL
	set rlist {}
	foreach record [WDB Search $key $long $date $max] {
	    dict with record {}
	    # these are admin pages, don't list them
	    if {[dict exists $protected $id]} continue
	    if {$type ne "" && ![string match "text/*" $type]} {
		lappend rlist [list [timestamp $date] [<a> href [file join $pageURL $id] $name] [<a> href [file join $pageURL $id] [<img> class imglink src [file join $mount image?N=$id] width 100 height 100]]]
	    } else {
		lappend rlist [list [timestamp $date] [<a> href [file join $pageURL $id] $name] {}]
	    }
	    set rdate $date
	    incr count
	}
	append result [list2table $rlist {Date Name Image} {}]
	append result "<br>\n"

	if {$count == 0} {
	    append result [<b> [<i> "No matches found"]]
	    set rdate 0
	} else {
	    append result [<b> [<i> "Displayed $count matches"]]
	    set rdate 0
	}


	return [list $result $rdate $long]
    }

    proc /searchp {r} {
	variable mount
	variable pageURL
	variable text_url
	# search page
	Debug.wikit {do: search page}
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
	    set r [sortable $r]
	    if {[dict exists $qd long]} {
		set long 1
	    }
#	    lassign [translate -1 "Search" $C .html] C U T BR
	    set T {}
	    set U {}
	    set BR {}
	    if { $nqdate } {
		append C [<p> [<a> href "search?S=[armour $term]&F=$nqdate&_charset_=utf-8" "More search results..."]]
	    }
	    if { $long } {
		append C <p> 
		append C [<a> href "search?S=[armour [string trimright $term *]]&_charset_=utf-8" "Repeat search in titles only"]
		append C ", or remove trailing asterisks from the search string to search the titles only.</p>"
	    } else {
		append C <p> 
		append C [<a> href "search?S=[armour $term*]&_charset_=utf-8" "Repeat search in titles and contents"]
		append C ", or append an asterisk to the search string to search the page contents as well as titles.</p>"
	    }
	    set q [string trimright $term *]
	    append q "%20site:" $text_url
	    variable gsearch
	    if {$gsearch} {
		append C [<p> [<a>  target _blank href "http://www.google.com/search?q=[armour $q]" "Click here to see all matches on Google Web Search"]]
	    }
	} else {
	    # send a search page
	    set search ""
	    set C ""
	}
	
	variable searchForm; set C "[subst $searchForm]$C"
	
	set name "Search"
	set Title "Search"
	set menu [menus Home Recent Help WhoAmI]
	set footer [menus Home Recent Help]

	return [sendPage $r spage]
    }

    proc /search {r {S ""} {long 0} args} {
	variable detect_robots
	if {$detect_robots && [dict get? $r -ua_class] eq "robot"} {
	    return [robot $r]
	}

	perms $r read

	if {$S eq "" && [llength $args] > 0} {
	    set S [lindex $args 0]
	}

	Debug.wikit {/search: '$S'}
	dict set r -prefix "/$S"
	dict set r -suffix $S

	return [/searchp $r]
    }
    
    proc do {r} {
	Debug.wikit {DO}
	perms $r read

	variable pageURL
	variable mount
	variable readonly

	# decompose name
	lassign [Url urlsuffix $r $pageURL] result r term path
	if {!$result} {
	    return $r	;# URL not in our domain
	}
	if {$term eq "/"} {
	    return [/welcome $r]
	}

	set N [file rootname $term]	;# it's a simple single page
	set ext [file extension $term]	;# file extension?
	Debug.wikit {WIKI DO: result:$result term:$term path:$path N:$N ext:'$ext'}

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
	    if {$N < 0} {
		# locate has given up - can't find a page - go to search
		Debug.wikit {do: can't find '$term' ... search for it}
		return [Http Redir $r [file join $mount search] S [Query decode $term$fancy]]
	    } elseif {$N ne $term} {
		# we really should redirect
		variable detect_robots
		Debug.wikit {do: can't find '$N' ne '$term' ... redirect to '[file join $pageURL $N]'}
		if {$detect_robots && [dict get? $r -ua_class] eq "robot"} {
		    # try to make robots always use the canonical form
		    return [Http Moved $r [file join $pageURL $N]]
		} else {
		    return [Http Redir $r [file join $pageURL $N]]
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

	# prevent some pages from being readable by any but admin
	variable rprotected
	if {$N in $rprotected} {
	    perms $r admin
	}

	set date [clock seconds]	;# default date is now
	set name ""	;# no default page name
	set who ""	;# no default editor
	set page_toc ""	;# default is no page toc
	set BR {}

	# simple page - non search term
	if {$N < 0 || $N >= [WDB PageCount]} {
	    Debug.wikit {do: invalid page}
	    return [Http NotFound $r]
	}

	# try cached version
	lassign [fromCache $r $N $ext] cached result
	if {$cached} {
	    Debug.wikit {do: cached version of $N $ext}
	    return $result
	}

	# set up a few standard URLs an strings
	lassign [WDB GetPage $N name date who type] name date who type
	if {$name eq ""} {
	    Debug.wikit {do: can't find $N in DB}
	    return [Http NotFound $r]
	} else {
	    Debug.wikit {do: found $N in DB, type:$type}
	}

	# binary pages are returned as-is, no decoration
	if {$type ne "" && ![string match text/* $type]} {
	    # Page is <img>, not the image itself
	    set C [<img> src [file join $pageURL $mount image?N=$N]]
	    # set up backrefs
	    set backRef [file join $mount ref]?N=$N
	    #set Refs "[<a> href $backRef Reference] - "
	    set Title [<a> href $backRef title "click to see reference to this page" $name]
	    # create menu and footer
	    set menu {}
	    set footer {}
	    variable protected
	    variable perms
	    if {[dict size $perms] > 0 || ![dict exists $protected $N]} {
		lappend menu {*}[menus HR]
		lappend menu [<a> href $backRef References]
	    }
	    set menu [menus Home Recent Help WhoAmI {*}$menu]
	    set footer [menus Home Recent Help Search WhoAmI {*}$footer]
	    lappend menu [<a> href [file join $mount edit]?N=$N Edit]
	    lappend footer [<a> href [file join $mount edit]?N=$N Edit]
	    lappend menu [<a> href [file join $mount history]?N=$N "History"]
	    # add read only header if needed
	    variable hidereadonly
	    if {$readonly ne "" && !$hidereadonly} {
		set ro "<it>(Read Only Mode: $readonly)</it>"
	    } else {
		set ro ""
	    }
	    set result [sendPage [Http CacheableContent $r $date] page DCache]
	    return $result
	} else {
	    # fetch page contents
	    set content [WDB GetContent $N]
	    variable protected
	    if {$N == [dict get? $protected ADMIN:Welcome]} {
		# page 0 is HTML and is the Welcome page
		# it needs to be redirected to the functional page
		# as it may reference maps
		return [Http Redir $r [file join $mount welcome]]
	    } else {
		switch -- $ext {
		    .txt -
		    .str -
		    .code {
			return [Http NoCache [Http Ok $r [translate $N $name $content $ext] text/plain]]
		    }
		    .xml {
			set C "<?xml version='1.0'?>"
			append C \n [pageXML $N]
			return [Http NoCache [Http Ok $r [translate $N $name $C $ext] text/xml]]
		    }
		    default {
			Debug.wikit {do: $N is a normal page}
			dict set r content-location "http://[Url host $r]/$N"
			lassign [translate $N $name $content $ext] C U page_toc BR IH DTl TNRl
			set C [DoctoolPages $r $C $DTl]
			set C [TclNRoffPages $r $C $TNRl]
			variable include_pages
			if {$include_pages} {
			    lassign [IncludePages $r $C $IH] r C
			}
			foreach {containerid bref} $BR {
			    if {[string length $bref]} {
				set brefpage [WDB LookupPage $bref]
			    } else {
				set brefpage $N
			    }
			    dict lappend r -postload [<script> "getBackRefs($brefpage,'$containerid');"]
			}
			set C [string map [list <<TOC>> $page_toc] $C]
		    }
		}
		Debug.wikit {do has translated $N}
		
		# set up backrefs
		set backRef [file join $mount ref]?N=$N
		#set Refs "[<a> href $backRef Reference] - "
		set Title [<a> href $backRef title "click to see reference to this page" $name]

		# add extra menu and footer elements
		set menu {}
		set footer {}
		variable protected
		variable perms
		if {[dict size $perms] > 0 || ![dict exists $protected $N]} {
		    lappend menu {*}[menus HR]
		    if {!$::roflag && $readonly eq {}} {
			lappend menu [<a> href [file join $mount edit]?N=$N&A=1 "Add comments"]
			lappend footer [<a> href [file join $mount edit]?N=$N&A=1 "Add comments"]
			lappend menu [<a> href [file join $mount edit]?N=$N Edit]
			lappend footer [<a> href [file join $mount edit]?N=$N Edit]
		    }
		    lappend menu [<a> href [file join $mount history]?N=$N "History"]
		    lappend menu [<a> href [file join $mount summary]?N=$N "Edit summary"]
		    lappend menu [<a> href $backRef References]
		}
	    }

	    # arrange the page's tail
	    set subtitle ""
	    if {$date != 0} {
		set update [clock format $date -gmt 1 -format {%Y-%m-%d %T}]
		set subtitle "Updated $update"
	    }

	    if {$who ne "" &&
		[regexp {^(.+)[,@]} $who - who_nick]
		&& $who_nick ne ""
	    } {
		append subtitle " by [<a> href /[WDB LookupPage $who_nick] $who_nick]"
	    }
	    if {[string length $subtitle]} {
		variable delta
		append subtitle " " [<a> class delta href [file join $mount diff]?N=$N#diff0 $delta]
	    }

	    # sendPage vars
	    set menu [menus Home Recent Help WhoAmI {*}$menu]
	    set footer [menus Home Recent Help Search WhoAmI {*}$footer]

	    variable hidereadonly
	    if {$readonly ne "" && !$hidereadonly} {
		set ro "<it>(Read Only Mode: $readonly)</it>"
	    } else {
		set ro ""
	    }

	    set result [sendPage [Http CacheableContent $r $date] page DCache]

	    variable pagecaching
	    if {$pagecaching} {
		if {[WDB pagecache exists $N]} {
		    WDB pagecache delete $N
		}
		WDB pagecache insert $N [dict get $result -content] [dict get $result content-type] [clock milliseconds] [dict get? $result -title]
	    }
	    return $result
	}
    }

    # Site WikitWub-specific defaults
    # These may be overwritten by command line, or by vars.tcl
    variable mount /_/		;# default direct URL prefix
    variable pageURL /		;# default page prefix
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
    variable detect_robots 1
    variable css_prefix ""
    variable script_prefix ""
    variable image_prefix ""

    proc init {args} {
	Debug.wikit {init: $args}
	variable {*}$args

	# set up static content prefixes
	variable css_prefix
	if {$css_prefix eq ""} {
	    set css_prefix /css/
	}
	foreach v {script image} {
	    variable ${v}_prefix
	    if {[set ${v}_prefix] eq ""} {
		set ${v}_prefix /$v 
	    }
	}

	variable htmlsuffix
	set htmlsuffix(wikit) [<script> src [file join $script_prefix wiki.js]]\n
	set htmlsuffix(stx) [<script> src [file join $script_prefix wiki.js]]\n
	set htmlsuffix(creole) [<script> src [file join $script_prefix wiki.js]][<script> src [file join $script_prefix creole.js]]\n

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
	if {![info exists wikitdbpath] || $wikitdbpath eq ""} {
	    if {[info exists ::starkit_wikitdbpath]} {
		set wikitdbpath $::starkit_wikitdbpath
	    } else {
		set wikitdbpath [file join $wikitroot $wikidb]
	    }
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

	variable protected_pages
	variable protected
	foreach n $protected_pages {
	    set v [WDB LookupPage $n]
	    if {$v ne ""} {
		dict set protected $n $v
	    }
	}
	foreach {n v} $protected {
	    dict set protected $v $n
	}

	Debug on WDB
	variable rprotected_pages
	variable rprotected
	foreach n $rprotected_pages {
	    set v [WDB LookupPage $n]
	    if {$v ne ""} {
		dict set rprotected $n $v
	    }
	}
	foreach {n v} $rprotected {
	    dict set rprotected $v $n
	}
	Debug off WDB

	# load the TOC page from the wiki
	reloadTOC

	variable roflag 
	set ::roflag $roflag

	# initialize RSS feeder
	variable wiki_title
	variable text_url
	catch {
	    WikitRss new \
		[expr {([info exists wiki_title] &&  $wiki_title ne "")?$wiki_title:"Tcler's Wiki"}] \
		"http://$text_url/"
	}

	variable pagecaching
	variable pagecache
	if {$pagecaching} {
	    # initialize page cache
	    WDB pagecache create
	}
	menus	;# call it to prime array
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

Debug.log {RESTART: [clock format [clock second]]}

Debug on wikit
Debug on WDB

# Initialize Site
Site start application WikitWub home [file normalize [file dirname [info script]]] ini wikit.ini
