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
		<description>[xmlarmour $Description] modified by [xmlarmour $Author]</description>
		</item>"
    }


    ###############################################################
    #
    # The remainder of this file generates the RSS file.
    #
    ###############################################################

    proc init {_db name baseurl} {
	#mk::file open DB $File -nocommit -readonly
	#mk::view layout DB.pages {name page date:I who}

	# The Wikit implementation has the Wiki name as the name of page 0.
	variable db $_db
	variable wikiName $name
	variable baseUrl $baseurl
	variable Name [mk::get $db.pages!0 name]
    }

    proc rss {} {
	variable db
	Debug.rss {rss request [clock seconds]}

	# Generate the XML file
	set contents [header]

	variable Name
	variable baseUrl

	# generate the channel information for the feed.  It says
	# what the name of the feed is (the same as the Wiki name), and where
	# the feed comes from (the Wiki URL).
	append contents "<channel>
	<title>$Name - Recent Changes</title>
	<link>$baseUrl</link>
	<description>Recent changes to $Name</description>
	"

	Debug.rss {filling details} 7

	# generate items for changed pages,
	# ordered from most recently changed to least recently changed.
	variable exclude
	variable MaxItems
	set i 0
	foreach page [mk::select $db.pages -rsort date] {
	    if {$page in $exclude} continue	;# exclude "Search" and "Recent Changes" pages

	    lassign [mk::get $db.pages!$page name date who] name date who
            set change [expr {[mk::view size wdb.pages!$page.changes] - 1 }] 
	    set changes [mk::view size wdb.pages!$page.changes!$change.diffs]  

	    Debug.rss {detail $name $date $who $page} 7

	    if {$changes > 1} {
		append contents [item $name $date $who $baseUrl$page "$changes lines"] \n
		incr i
		if {$i > $MaxItems} break	;# limit RSS size
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
