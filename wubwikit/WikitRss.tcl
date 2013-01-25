#! /usr/bin/env tclkit
Debug define rss 0
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

    proc new {name baseurl {_stale 0}} {
	# The Wikit implementation has the Wiki name as the name of page 0.
	variable wikiName $name
	variable baseUrl $baseurl
	variable Name [WDB GetPage 0 name]
	variable cache ""
	if {$_stale == 0} {
	    variable stale [expr {60 * 60}]	;# an hour between refreshes
	} else {
	    variable stale
	}
    }

    # clear the cached RSS
    # it actually just records the time of last change
    proc clear {} {
	#variable cache ""
	Debug.rss {rss clear [info level -1]}
	variable changed [clock seconds]
    }
    
    proc rss {} {

	Debug.rss {rss request [clock seconds]}
	variable changed
	if {![info exists changed]} {
	    set changed [clock seconds]
	}

	# only regenerate the cached rss if it's stale
	variable cache; variable stale
	if {$cache ne ""} {
	    if {[clock seconds] - $changed < $stale} {
		Debug.rss {rss return cached [clock seconds]}
		return $cache	;# return the cache if it's not stale
	    }
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
	
	set i 0
	set D 3
	set edate [expr {[clock seconds]-$D*86400}]
	set pages [WDB RecentChanges $edate]
	foreach pager $pages {

	    #puts "$pager"

	    dict with pager {}

	    if {$id in $exclude} continue	;# exclude "Search" and "Recent Changes" pages
	    
	    set changes ""

	    # look for changes in past D days
	    set changes {}
	    set delta 0
	    set whol {}
	    set V [WDB Versions $id]
	    if {$V > 0} {
		foreach record [WDB Changes $id $edate] {
		    dict update record date cdate who cwho delta cdelta version version {}
		    #puts "incr delta [expr {int(abs($cdelta))}]"
		    incr delta [expr {int(abs($cdelta))}]
		    # set C [WikitWub::summary_diff $id $V [expr {$V-1}] 1]
		    # if {[regexp {^[[:print:]\r\n]*$} $C]} {
		    # 	append changes $C\n
		    # } else {
		    # 	append changes "Could not render difference for version $V\n"
		    # }
		    lappend whol $who
		    incr V -1
		    if {$V < 1} break
		    if {$cdate<$edate} break
		    set date $cdate
		    set who $cwho
		}
	    }
	    
	    #Debug.rss {detail $name $date $who $id} 7

	    if {$delta > 0} {
		append contents [item $name $date [join [lsort -unique $whol] ", "] $baseUrl$id " ($delta characters)\n$changes"] \n
		if {[incr i] > $MaxItems} break	;# limit RSS size
	    }
	}

	append contents "</channel>\n"
	append contents "</rss>\n"
	Debug.rss {completed}
	    
	set cache $contents

	return $contents
    }

    namespace export -clear *
    namespace ensemble create -subcommands {}
}

Debug off rss 10
