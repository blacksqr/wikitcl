namespace eval Db {
    variable pageV
    variable refV

    # return the 'from' field from refs from a given page
    proc from {page} {
	return [$refV get $page from]
    }

    # return those ref records which refer to $page
    proc to {page} {
	return [$refV select -exact to $page]
    }
    
    # return content size of a page
    proc contentsize {pid} {
	return [$pageV get $i -size page]
    }

    # return page content
    proc getcontent {id} {
	return [getpage $id page]
    }

    # return named fields from a page
    proc getpage {pid args} {
	return [$pageV get $pid {*}$args]
    }

    # return number of versions of a page
    proc versions {page} {
	set changes [$pageV open $pid changes]
	set result [$changes size]
	$changes close
	return $result
    }

    # return named fields from a version of a page
    proc getchange {pid sid args} {
	set changes [$pageV open $pid changes]
	set result [$changes get $sid {*}$args]
	$changes close
	return $result
    }

    # return size of a changeset
    proc changesetsize {pid sid} {
	set changes [$pageV open $pid changes]
	set diffs [$changes open $sid diffs]
	set result [$diffs size]
	$changes close
	$diffs close
	return $result
    }

    # return number of pages
    proc pagecount {} {
	return [mk::view size wdb.pages]
    }

    proc mostrecentchange {pid date} {
	set changes [$pageV open $pid changes]
	set dl [$changes select -max date $date -rsort date]
	if {[llength $dl] == 0} {
	    set dl [$changes select -rsort date]
	}
	return [lindex $dl 0]
    }

    # search for text
    # key - a list of words
    # long - search in content as well as name
    # date - if non-0, search more recent pages than date
    proc search {key long date} {
	set fields name
	if {$long} {
	    lappend fields page
	}

	set search {}
	foreach k [split $key " "] {
	    if {$k ne ""} {
		lappend search -keyword $fields $k
	    }
	}

	if {$date == 0} {
	    set rows [$pageV select -rsort date {*}$search]
	} else {
	    set rows [$pageV select -max date $date -rsort date {*}$search]
	}
	return $rows
    }

    proc recent {threshold} {
	set result [$pageV select -min date $threshold -min name " " -rsort date]
	return [lrange $result 0 99]
    }

    proc pageByName {name} {
	return [$pageV select name $name -min date 1]
    }

    proc pageGlobName {glob} {
	return [$pageV select -glob name $glob -min date 1]
    }

    proc cleared {} {
	set result [$pageV select -min date 1 -max page " " -rsort date]
	return [lrange $result 0 99]
    }

    proc changesSince {pid date} {
	set changes [$pageV open $pid changes]
	set result [$changes select -min date $date -rsort date]
	$changes close
	return $result
    }

    # return all valid pages
    proc allpages {} {
	return [$pageV select -first 11 -min date 1 -sort date]
    }

    proc changes {pid} {
	set changes [$pageV open $pid changes]
	set result [$changes select -rsort date]
	$changes close
	return $result
    }

    #----------------------------------------------------------------------------
    #
    # ListPageVersions --
    #
    #	Enumerates the available versions of a page in the database.
    #
    # Parameters:
    #     id - Row id in the 'pages' view of the page being queried.
    #     limit - Maximum number of versions to return (default is all versions)
    #     start - Number of versions to skip before starting the list
    #		(default is 0)
    #
    # Results:
    #	Returns a list of tuples comprising the following elements
    #	    version - Row ID of the version in the 'changes' view,
    #                   with a fake row ID of one past the last row for
    #		      the current version.
    #         date - Date and time that the version was committed,
    #                in seconds since the Epoch
    #         who - String identifying the user that committed the version
    #
    #----------------------------------------------------------------------------

    proc ListPageVersionsDB {id {limit Inf} {start 0}} {

	# Special case for the fake pages

	switch $id {
	    2 - 4 {
		return [list [list 0 [clock seconds]
			      {Version information not maintained for this page}]]
	    }
	}

	# Determine the number of the most recent version
	set results [list]
	set mostRecent [versions $id]

	# List the most recent version if requested
	if {$start == 0} {
	    lassign [getpage $id date who] date who
	    lappend results [list $mostRecent $date $who]
	    incr start
	}

	# Do earlier versions as needed
	set changes [$pageV open $id changes]
	set idx [expr {$mostRecent - $start}]
	while {$idx >= 0 && [llength $results] < $limit} {
	    lassign [$changes get $idx date who] date who
	    lappend results [list $idx $date $who]
	    incr idx -1
	}
	$changes close
	return $results
    }

    #----------------------------------------------------------------------------
    #
    # GetPageVersion --
    #
    #     Retrieves a historic version of a page from the database.
    #
    # Parameters:
    #     id - Row ID in the 'pages' view of the page being queried.
    #     version - Version number that is to be retrieved (row ID in
    #               the 'changes' subview)
    #	db - Handle to the database where the Wiki is stored.
    #
    # Results:
    #     Returns page text as Wikitext. Throws an error if the version
    #     is non-numeric or out of range.
    #
    #----------------------------------------------------------------------------

    proc GetPageVersion {id {version {}}} {
	return [join [GetPageVersionLines $id $version] \n]
    }
    proc GetPageVersionLines {id {version {}}} {
	set page [$pageV get $id]
	set latest [versions $id]
	if {$version eq {}} {
	    set version $latest
	}
	if {![string is integer $version] || $version < 0} {
	    return -code error "bad version number \"$version\":\
                          must be a positive integer" \
		-errorcode {wiki badVersion}
	}
	if {$version > $latest} {
	    return -code error "cannot get version $version, latest is $latest" \
		-errorcode {wiki badVersion}
	}
	if {$version == $latest} {
	    return [split $page \n]
	}
	set v $latest
	set lines [split $page \n]
	set changes [$pageV open $id changes]
	while {$v > $version} {
	    incr v -1
	    set i [changesetsize $id $v]
	    set diffs [$changes open $v diffs]
	    while {$i > 0} {
		incr i -1
		
		dict with [$diffs get $i]
		if {$from <= $to} {
		    set lines [eval [linsert $old 0 \
					 lreplace $lines[set lines {}] $from $to]]
		} else {
		    set lines [eval [linsert $old 0 \
					 linsert $lines[set lines {}] $from]]
		}
	    }
	    $diffs close
	}
	$changes close
	return $lines
    }

    #----------------------------------------------------------------------------
    #
    # AnnotatePageVersion --
    #
    #     Retrieves a version of a page in the database, annotated with
    #     information about when changes appeared.
    #
    # Parameters:
    #	id - Row ID in the 'pages' view of the page to be annotated
    #	version - Version of the page to annotate.  Default is the current
    #               version
    #	db - Handle to the Wikit database.
    #
    # Results:
    #	Returns a list of lists. The first element of each sublist is a line
    #	from the page.  The second element is the number of the version
    #     in which that line first appeared. The third is the time at which
    #     the change was made, and the fourth is a string identifying who
    #     made the change.
    #
    #----------------------------------------------------------------------------

    proc AnnotatePageVersion {id {version {}}} {
	set latest [versions $id]
	if {$version eq {}} {
	    set version $latest
	}
	if {![string is integer $version] || $version < 0} {
	    return -code error "bad version number \"$version\":\
                          must be a positive integer" \
		-errorcode {wiki badVersion}
	}
	if {$version > $latest} {
	    return -code error "cannot get version $version, latest is $latest" \
		-errorcode {wiki badVersion}
	}

	# Retrieve the version to be annotated

	set lines [GetPageVersionLines $id $version]
	set changes [$pageV open $id changes]

	# Start the annotation by guessing that all lines have been there since
	# the first commit of the page.

	if {$version == $latest} {
	    lassign [getpage $id date who] date who
	} else {
	    lassign [$changes get $version date who] date who
	}
	if {$latest == 0} {
	    set firstdate $date
	    set firstwho $who
	} else {
	    lassign [$changes get 0 date who] firstdate firstwho
	}
	
	# versions has one entry for each element in $lines, and contains
	# the version in which that line first appeared.  We guess version
	# 0 for everything, and then fill in later versions by working backward
	# through the diffs.  Similarly 'dates' has the version dates and
	# 'whos' has the users that committed the versions.
	set versions [struct::list repeat [llength $lines] 0]
	set dates [struct::list repeat [llength $lines] $date]
	set whos [struct::list repeat [llength $lines] $who]

	# whither contains, for each line a version being examined, the line
	# index corresponding to that line in 'lines' and 'versions'. An index
	# of -1 indicates that the version being examined is older than the
	# line
	set whither [list]
	for {set i 0} {$i < [llength $lines]} {incr i} {
	    lappend whither $i
	}
	
	# Walk backward through all versions of the page
	while {$version > 0} {
	    incr version -1

	    # Walk backward through all changes applied to a version
	    set i [changesetsize $id $version]
	    lassign [$changes get $version date who] lastdate lastwho
	    set diffs [$changes open $version diffs]
	    while {$i > 0} {
		incr i -1
		lassign [$diffs get $i from to old] from to old
		
		# Update 'versions' for all lines that first appeared in the
		# version following the one being examined

		for {set j $from} {$j <= $to} {incr j} {
		    set w [lindex $whither $j]
		    if {$w > 0} {
			lset versions $w [expr {$version + 1}]
			lset dates $w $date
			lset whos $w $who
		    }
		}

		# Update 'whither' to preserve correspondence between the version
		# being examined and the one being annotated.  Lines that do
		# not exist in the annotated version are marked with -1.

		if {[llength $old] == 0} {
		    set m1s {}
		} else {
		    set m1s [struct::list repeat [llength $old] -1]
		}
		if {$from <= $to} {
		    set whither [eval [linsert $m1s 0 \
					   lreplace $whither[set whither {}] $from $to]]
		} else {
		    set whither [eval [linsert $m1s 0 \
					   linsert $whither[set whither {}] $from]]
		}
	    }
	    $diffs close
	    set date $lastdate
	    set who $lastwho
	}
	$changes close

	set result {}
	foreach line $lines v $versions date $dates who $whos {
	    lappend result [list $line $v $date $who]
	}
	return $result
    }

    # addRefs - a newly created page $id contains $refs references to other pages
    # Add these references to the .ref view.
    proc addRefs {id refs} {
	if {$id != 2 && $id != 4} {
	    foreach x $refs {
		if {$id != $x} {
		    $refV insert end from $id to $x
		}
	    }
	}
    }

    # delRefs - remove all references from page $id to anywhere
    proc delRefs {id} {
	set v [mk::select $db.refs from $id]	;# the set of all references from $id

	# delete from last to first
	set n [llength $v]
	while {[incr n -1] >= 0} {
	    $refV delete [lindex $v $n]
	}
    }

    # FixPageRefs - recreate the entire refs view
    proc FixPageRefs {{db wdb}} {
	mk::view size $db.refs 0	;# delete all contents from the .refs view

	# visit each page, recreating its refs
	mk::loop c $db.pages {
	    set id [mk::cursor position c]
	    pagevarsDB $db $id date page
	    if {$date != 0} {
		# add the references from page $id to .refs view
		addRefs $id $db [StreamToRefs [TextToStream $page] [list ::Wikit::InfoProc $db]]
	    }
	}
	DoCommit
    }

    #----------------------------------------------------------------------------
    #
    # UpdateChangeLog --
    #     Updates the change log of a page.
    #
    # Parameters:
    #     id - Row ID in the 'pages' view of the page being updated
    #     name - Name that the page had *before* the current version.
    #     date - Date of the last update of the page *prior* to the one
    #            being saved.
    #     who - String identifying the user that updated the page last
    #           *prior* to the version being saved.
    #     page - Previous version of the page text
    #     text - Version of the page text now being saved.
    #
    # Results:
    #	None
    #
    # Side effects:
    #	Updates the 'changes' view with the differences that recnstruct
    #     the previous version from the current one.
    #
    #----------------------------------------------------------------------------

    proc UpdateChangeLog {id name date who page text} {

	# Store summary information about the change
	set version [versions $id]
	set changes [$pageV open $id changes]
	$changes insert end date $date who $who
	set diffs [$changes open $version diffs]

	# Determine the changed lines
	set linesnew [split $text \n]
	set linesold [split $page \n]
	set lcs [::struct::list longestCommonSubsequence2 $linesnew $linesold 5]
	set changes [::struct::list lcsInvert \
			 $lcs [llength $linesnew] [llength $linesold]]

	# Store change information in the database
	set i 0
	set change 0	;# record magnitude of change
	foreach tuple $changes {
	    foreach {action newrange oldrange} $tuple break
	    switch -exact -- $action {
		deleted {
		    foreach {from to} $newrange break
		    set old {}

		    incr change [string length [lrange $linesnew $from $to]]
		}
		added  {
		    foreach {to from} $newrange break
		    foreach {oldfrom oldto} $oldrange break
		    set old [lrange $linesold $oldfrom $oldto]

		    incr change [expr {abs([string length [lrange $linesnew $from $to]] \
					       - [string length $old])}]
		}
		changed  {
		    foreach {from to} $newrange break
		    foreach {oldfrom oldto} $oldrange break
		    set old [lrange $linesold $oldfrom $oldto]

		    incr change [expr {abs([string length [lrange $linesnew $from $to]] \
					       - [string length $old])}]
		}
	    }
	    $diffs insert end from $from to $to old $old
	    incr i
	}

	$changes set $version delta $change	;# record magnitude of changes
	$changes close
	$diffs close
    }

    # SavePage - store page $id ($who, $text, $newdate)
    proc SavePage {id text newWho newName {newdate ""} {commit 1}} {
	puts "SavePageDB@[clock seconds] start"

	set changed 0

	variable mutex;
	if {$mutex ne ""} {
	    puts "SavePageDB@[clock seconds] lock"
	    ::thread::mutex lock $mutex	;# lock for update
	}

	if {[catch {
	    puts "SavePageDB@[clock seconds] pagevarsDB"
	    lassign [getpage $id name date page who] name date page who

	    if {$newName != $name} {
		puts "SavePageDB@[clock seconds] new name"
		set changed 1

		# rewrite all pages referencing $id changing old name to new
		# Special case: If the name is being removed, leave references intact;
		# this is used to clean up duplicates.
		if {$newName != ""} {
		    foreach x [mk::select $db.refs to $id] {
			set x [$refV get $x from]
			set y [$pageV get $x page]
			$pageV set $x page [replaceLink $y $name $newName]
		    }
		    
		    # don't forget to adjust links in this page itself
		    set text [replaceLink $text $name $newName]
		}

		$pageV set $id name $newName
	    }

	    if {$newdate != ""} {
		puts "SavePageDB@[clock seconds] set date"
		# change the date if requested
		$pageV set $id date $newdate
	    }

	    # avoid creating a log entry and committing if nothing changed
	    set text [string trimright $text]
	    if {$changed || $text != $page} {
		puts "SavePageDB@[clock seconds] parse"
		# make sure it parses before deleting old references
		set newRefs [StreamToRefs [TextToStream $text] [list ::Wikit::InfoProc $db]]
		puts "SavePageDB@[clock seconds] delRefs"
		delRefs $id $db
		puts "SavePageDB@[clock seconds] addRefs"
		addRefs $id $db $newRefs

		# If this isn't the first time that the given page has been stored
		# in the databse, make a change log entry for rollback.

		puts "SavePageDB@[clock seconds] log change"
		mk::set $db.pages!$id page $text who $newWho
		if {$page ne {} || [mk::view size $db.pages!$id.changes]} {
		    puts "SavePageDB@[clock seconds] update change log"
		    UpdateChangeLog $db $id $name $date $who $page $text
		}

		if {$newdate == ""} {
		    puts "SavePageDB@[clock seconds] set date"
		    $pageV set $id date [clock seconds]
		    set commit 1
		}

		puts "SavePageDB@[clock seconds] done saving"
	    }
	} r]} {
	    Debug.error "SavePageDb: '$r'"
	}

	if {$commit} {
	    puts "SavePageDB@[clock seconds] commit"
	    mk::file commit $db
	}

	if {$mutex ne ""} {
	    puts "SavePageDB@[clock seconds] unlock mutex"
	    ::thread::mutex unlock $mutex	;# unlock for db update
	}
        puts "SavePageDB@[clock seconds] done."
    }

    proc WikiDatabase {name {db wdb} {shared 0}} {
	variable readonly
	variable wikifile $name

	if {[lsearch -exact [mk::file open] $db] == -1} {
	    if {$readonly == -1} {
		if {[file exists $name] && ![file writable $name]} {
		    set readonly 1
		} else {
		    set readonly 0
		}
	    }

	    set flags {}
	    if {$readonly} {
		lappend flags -readonly
		set tst readable
	    } else {
		set tst writable
	    }

	    if {$shared} {
		lappend flags -shared
	    }

	    set msg ""
	    if {[catch {eval mk::file open $db $name -nocommit $flags} msg]
		&& [file $tst $name]} {

		# if we can write and/or read the file but can't open
		# it using mk then it is almost always inside a starkit,
		# so we copy it to memory and open it from there

		set readonly 1
		mk::file open $db
		set fd [open $name]
		mk::file load $db $fd
		close $fd
		set msg ""
	    }

	    if {$msg != "" && ![string equal $msg $db]} {
		error $msg
	    }

	    # if there are no references, probably it's the first time, so recalc
	    if {!$readonly && [mk::view size $db.refs] == 0} {
		# this can take quite a while, unfortunately - but only once
		::Wikit::FixPageRefs
	    }
	}
    }

    # LookupPage - find a named page
    proc LookupPage {name} {
	set lcname [string tolower $name]
	set n [$pageV find name $name]
	if {$n == ""} {
	    $pageV insert end name $name
	    mk::file commit $db
	    set n [pagecount]
	}
	return $n
    }

    namespace export -clear *
    namespace ensemble create -subcommands {}
}
