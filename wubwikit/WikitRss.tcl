#! /usr/bin/env tclkit

package require Mk4tcl
package require Html
package provide WikitRss 1.0

###############################################################
#
# Configure this script using three simple variables!
# - File contains the name of the Wikit database,
#   typically called "wikit.tkd".
# - baseUrl contains the URL of the Wiki.  This shouldn't
#   have a page number (or a trailing /), as it's used toi
#   generate the links for changed pages.
# - MaxItems specifies the maximum number of changed pages to include
#   in the RSS feed.
#
###############################################################
namespace eval WikitRss {
    variable db
    variable baseUrl http://wiki.tcl.tk
    variable MaxItems 25
    variable cache

    ###############################################################
    #
    # The following constants are used to hide magic numbers
    #
    ###############################################################

    variable exclude {2 4 5}

    ###############################################################
    #
    # The following procedures are used to generate the RSS feed.
    #
    ###############################################################

    # genHeader generates the header of the XML file.  Basically, it tells
    # what version of RSS is being used.
    #
    # No parameters are expected.
    proc header {} {
	return "<?xml version='1.0'?>
  	<rss version='0.91'>
	"
    }

    # item generates a single news item for the feed.
    # Each item is a different Wiki page.
    #
    # Four parameters are required:
    # - Title: the title of the Wiki page
    # - Time: the time (in "[clock seconds]" format) that the Wiki page
    #   was last modified
    # - Author: who last changed the Wiki page
    # - Url: the URL of the Wiki page
    #
    # You may not like the format that I've chosen to display the
    # news item name in.  It's pretty easy to change.
    # See the lines I've commented out for alternate formats.

    proc item {Title Time Author Url {Description ""}} {
	set time [clock format $Time -format "%a, %d %b %Y %T GMT" -gmt 1]
	return "<item>
		<title>[xmlarmour $Title]</title>
		<link>$Url</link>
		<pubDate>$time</pubDate>
		<description>Modified by [xmlarmour $Author][xmlarmour $Description] </description>
		</item>"
    }


    ###############################################################
    #
    # The remainder of this file generates the RSS file.
    #
    ###############################################################

    proc new {_db name baseurl} {
	#mk::file open DB $File -nocommit -readonly
	#mk::view layout DB.pages {name page date:I who}

	# The Wikit implementation has the Wiki name as the name of page 0.
	variable db $_db
	variable wikiName $name
	variable baseUrl $baseurl
	variable Name [mk::get $db.pages!0 name]
	variable cache ""
    }

    # clear the cached RSS
    proc clear {} {
	variable cache ""
    }
    
    proc rss {} {
	variable db
	Debug.rss {rss request [clock seconds]}

	variable cache
	if {$cache ne ""} {
	    return $cache
	}

	# Generate the XML file
	set contents [header]

	variable Name
	variable baseUrl
	variable exclude
	variable MaxItems

	# generate the channel information for the feed.  It says
	# what the name of the feed is (the same as the Wiki name), and where
	# the feed comes from (the Wiki URL).
	append contents "<channel>
	<title>$Name - Recent Changes</title>
	<link>$baseUrl</link>
	<description>Recent changes to $Name</description>
	"
	
	Debug.rss {filling details} 7
	
	if {0} {
	    # generate items for changed pages,
	    # ordered from most recently changed to least recently changed.
	    
	    # look for edit dates in pages.changes!
	    # look for changes in past D days
	    set D 10
	    set edate [expr {[clock seconds]-$D*86400}]
	    set changes {}

	    set pages [mk::select $db.pages -rsort date]
	    foreach N $pages {
		if {$N in $exclude} continue	;# exclude "Search" and "Recent Changes" pages
		lassign [mk::get $db.pages!$N name date who] name date who
		if {$date<$edate} break
		
		set V [mk::view size wdb.pages!$N.changes]
		foreach sid [mk::select wdb.pages!$N.changes -rsort date] {
		    lassign [mk::get wdb.pages!$N.changes!$sid date who delta] cdate cwho cdelta
		    set C [WikitWub::summary_diff $N $V [expr {$V-1}] 1]
		    lappend changes [list $name $date $cdelta $who $N $V $C]
		    incr V -1
		    if {$V < 1} break
		    if {$cdate<$edate} break
		    set date $cdate
		    set who $cwho
		}
	    }	
	    
	    set i 0
	    set changes [lsort -integer -decreasing -index 1 $changes]
	    foreach change $changes {
		lassign $change name date delta who N V C
		append contents [item $name $date $who $baseUrl$N " ($delta characters)\n$C"] \n
		if {[incr i] > $MaxItems} break	;# limit RSS size
	    }
	}

	set i 0
	set edate [expr {[clock seconds]-$D*86400}]
	set pages [mk::select $db.pages -rsort date]
	foreach page $pages {
	    if {$page in $exclude} continue	;# exclude "Search" and "Recent Changes" pages
	    
	    lassign [mk::get $db.pages!$page name date who] name date who
	    
	    if {$date<$edate} break

	    # calculate line change
	    set change [expr {[mk::view size wdb.pages!$page.changes] - 1}]
	    if {$change < 0} continue

	    # look for changes in past D days
	    set D 3
	    set edate [expr {[clock seconds]-$D*86400}]
	    set changes {}
	    set V [mk::view size wdb.pages!$page.changes]
	    set delta 0
	    set whol {}
	    foreach sid [mk::select wdb.pages!$page.changes -rsort date] {
		lassign [mk::get wdb.pages!$page.changes!$sid date who delta] cdate cwho cdelta
		incr delta [expr {int(abs($cdelta))}]
		set C [WikitWub::summary_diff $page $V [expr {$V-1}] 1]
		append changes $C\n
		lappend whol $who
		incr V -1
		if {$V < 1} break
		if {$cdate<$edate} break
		set date $cdate
		set who $cwho
	    }
	    
	    Debug.rss {detail $name $date $who $page} 7
	    
	    if {$delta > 0} {
		append contents [item $name $date [join [lsort -unique $whol] ", "] $baseUrl$page " ($delta characters)\n$changes"] \n
		if {[incr i] > $MaxItems} break	;# limit RSS size
	    }
	}

	append contents "</channel>\n"
	append contents "</rss>\n"
	Debug.rss {completed}
	return $contents
    }

    namespace export -clear *
    namespace ensemble create -subcommands {}
}

Debug off rss 10
