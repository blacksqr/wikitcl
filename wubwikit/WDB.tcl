package require OO
package provide WDB 1.0

Debug on WDB 10

namespace eval WDB {
    variable pageV
    variable refV
    variable readonly 0

    proc commit {} {
	variable db
	mk::file commit $db
    }
    
    #----------------------------------------------------------------------------
    #
    # s2l --
    #
    #	convert a select-view to a list of records
    #
    # Parameters:
    #	view - a mk4too view resulting from a select
    #	max - maximum number of records to return
    #
    # Results:
    #	Returns a list of dicts, each is a record corresponding to the
    #	select result.
    #
    #	Beware: this only works on mk4too selects which have specified a -sort
    #	or -rsort argument.  Other selects return a view containing index.
    #
    #----------------------------------------------------------------------------
    proc s2l {view {max -1}} {
	set result {}
	set size [$view size]
	if {$max > 0 && $size > $max} {
	    set size $max
	}
	for {set i $size} {$i < $size} {incr i} {
	    lappend result [$view get $i]
	}
	$view close
	return $result
    }

    #----------------------------------------------------------------------------
    #
    # i2l --
    #
    #	convert a select-view of indices to a list of records
    #
    # Parameters:
    #	original - the view over which the select ran
    #	select - the view resulting from the mk4too select
    #
    # Results:
    #	Returns a list of dicts, each is a record corresponding to the
    #	select result.
    #
    #	Beware: this only works on mk4too selects which haven't specified a -sort
    #	or -rsort argument.  Other selects return a copy of the original record
    #
    #----------------------------------------------------------------------------
    proc i2l {original select} {
	set result {}
	set size [$select size]
	for {set i 0} {$i < $size} {incr i} {
	    lappend result [$original get [$select get $i index]]
	}
	$select close
	return $result
    }

    #----------------------------------------------------------------------------
    #
    # ReferencesTo --
    #
    #	return list of page indices of those pages which refer to a given page
    #
    # Parameters:
    #	page - the page index of the page which we want all references to
    #
    # Results:
    #	Returns a list ints, each is an index of a page which contains a reference
    #	to the $page page.
    #
    #----------------------------------------------------------------------------
    proc ReferencesTo {page} {
	variable refV
	return [i2l $refV [$refV select -exact to $page]]
    }
    
    #----------------------------------------------------------------------------
    #
    # GetPage --
    #
    #	return named fields from a page
    #
    # Parameters:
    #	pid - the page index of the page whose metadata we want
    #	args - a list of field names whose values we want
    #
    # Results:
    #	Returns a list of values corresponding to the field values of those fields
    #	whose names are given in $args
    #
    #----------------------------------------------------------------------------
    proc GetPage {pid args} {
	variable pageV
	set result [$pageV get $pid {*}$args]
	Debug.WDB {GetPage $pid $args -> ($result)}
	return $result
    }

    #----------------------------------------------------------------------------
    #
    # GetContent --
    #
    #	return page content
    #
    # Parameters:
    #	pid - the page index of the page whose content we want
    #
    # Results:
    #	the string content of a page
    #
    #----------------------------------------------------------------------------
    proc GetContent {pid} {
	return [GetPage $pid page]
    }

    #----------------------------------------------------------------------------
    #
    # GetPageVars --
    #
    #	set variables in the caller corresponding to the page fields named in $args
    #
    # Parameters:
    #	pid - the page index of the page whose fields we want
    #	args - a list of field names whose values we want
    #
    # Results:
    #	operates only by side-effect, setting the named vars in the caller
    #
    #----------------------------------------------------------------------------
    proc GetPageVars {pid args} {
	variable pageV
	set record [$pageV get $pid]
	dict for n $args {
	    uplevel 1 [list set $n [dict get? $n]]
	}
    }

    #----------------------------------------------------------------------------
    #
    # PageCount --
    #
    #	return total number of pages
    #
    # Parameters:
    #
    # Results:
    #	Returns the total number of pages in the database
    #
    #----------------------------------------------------------------------------
    proc PageCount {} {
	variable pageV
	return [$pageV size]
    }

    #----------------------------------------------------------------------------
    #
    # Versions --
    #
    #	return number of versions of a page
    #
    # Parameters:
    #	pid - the page index of the page whose version count we want
    #
    # Results:
    #	an integer representing the number of versions of the page $pid
    #
    #----------------------------------------------------------------------------
    proc Versions {pid} {
	variable pageV
	set changeV [$pageV open $pid changes]
	set result [$changeV size]
	$changeV close
	return $result
    }

    #----------------------------------------------------------------------------
    #
    # GetChange --
    #
    #	return named fields from a version of a page
    #
    # Parameters:
    #	pid - the page index of the page whose changes we want
    #	sid - the page index of the changes whose fields we want
    #	args - a list of field names whose values we want
    #
    # Results:
    #	Returns a list of values corresponding to the field values of those fields
    #
    #----------------------------------------------------------------------------
    proc GetChange {pid sid args} {
	variable pageV
	set changeV [$pageV open $pid changes]
	set result [$changeV get $sid {*}$args]
	$changeV close
	return $result
    }

    #----------------------------------------------------------------------------
    #
    # ChangeSetSize --
    #
    #	return size of a changeset
    #
    # Parameters:
    #	pid - the page index of the page whose changeset we're interested in
    #	sid - the changeset index whose size we want
    #
    # Results:
    #	Returns an integer, being the size of the changeset
    #
    #----------------------------------------------------------------------------
    proc ChangeSetSize {pid sid} {
	variable pageV
	set changeV [$pageV open $pid changes]
	set diffV [$changeV open $sid diffs]
	set result [$diffV size]
	$changeV close
	$diffV close
	return $result
    }

    #----------------------------------------------------------------------------
    #
    # MostRecentChange --
    #
    #	return most recent change before a given date
    #
    # Parameters:
    #	pid - the page index of the page whose changeset we're interested in
    #	date - the latest change date we're interested in
    #
    # Results:
    #	Returns the change record of the most recent change
    #
    #----------------------------------------------------------------------------
    proc MostRecentChange {pid date} {
	variable pageV
	set changeV [$pageV open $pid changes]
	set dl [$changeV select -max date $date -rsort date]
	if {[$dl size] == 0} {
	    $dl close
	    set dl [$changeV select -rsort date]
	}
	set result [$dl get 0]
	$dl close
	return $result
    }

    #----------------------------------------------------------------------------
    #
    # RecentChanges --
    #
    #	return 100 most recent changes more recent than a given date
    #
    # Parameters:
    #	date - the latest change date we're interested in
    #
    # Results:
    #	Returns the change record of the most recent change
    #
    #----------------------------------------------------------------------------
    proc RecentChanges {date} {
	variable pageV
	return [s2l [$pageV select -min date $date -min name " " -rsort date] 100]
    }

    #----------------------------------------------------------------------------
    #
    # Changes --
    #
    #	return changes to a given page (optionally: since a date)
    #
    # Parameters:
    #	pid - page index of page whose changes we're interested in
    #	date - the latest change date we're interested in, or 0 for all
    #
    # Results:
    #	Returns the change record of matching changes
    #
    #----------------------------------------------------------------------------
    proc Changes {pid {date 0}} {
	variable pageV
	set changeV [$pageV open $pid changes]
	if {$date} {
	    set since [list -min date $date]
	} else {
	    set since {}
	}
	set result [$changeV select {*}$since -rsort date]
	$changeV close
	return [s2l $result]
    }

    #----------------------------------------------------------------------------
    #
    # Search --
    #
    #	search for text in page titles and/or content
    #
    # Parameters:
    #	key - a list of words
    #	long - search in content as well as name
    #	date - if non-0, search more recent pages than date
    #
    # Results:
    #	Returns a list of matching records
    #
    #----------------------------------------------------------------------------
    proc Search {key long date} {
	variable pageV
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
	    set maxdate {}
	} else {
	    set maxdate [list -max date $date]
	}
	set rows [$pageV select -min id 11 -min date 1 {*}$maxdate -rsort date {*}$search]

	return [s2l $rows]
    }

    #----------------------------------------------------------------------------
    #
    # LookupPage --
    #
    #	find a named page, creating it if necessary
    #
    # Parameters:
    #	name - name of page
    #
    # Results:
    #	Returns index of page
    #
    #----------------------------------------------------------------------------
    proc LookupPage {name} {
	variable pageV
	Debug.WDB {LookupPage '$name'}
	set lcname [string tolower $name]
	set n [$pageV find name $name]
	if {$n == ""} {
	    set n [pagecount]
	    Debug.WDB {LookupPage '$name' not found, added $n}
	    $pageV insert end name $name id $n
	    commit
	}
	return $n
    }

    #----------------------------------------------------------------------------
    #
    # PageByName --
    #
    #	find a named page
    #
    # Parameters:
    #	name - name of page
    #
    # Results:
    #	Returns a list of matching records
    #
    #----------------------------------------------------------------------------
    proc PageByName {name} {
	variable pageV
	set result [$pageV find name $name]
	Debug.WDB {PageByName '$name' -> $result}
	return $result
    }

    #----------------------------------------------------------------------------
    #
    # PageGlobName --
    #
    #	find page whose name matches a glob
    #
    # Parameters:
    #	glob - page name glob
    #
    # Results:
    #	Returns matching record
    #
    #----------------------------------------------------------------------------
    proc PageGlobName {glob} {
	variable pageV
	set select [$pageV select -glob name $glob -min date 1]
	set result [$pageV get [$select get 0]]
	$select close
	Debug.WDB {PageGlobName '$glob' -> $result}
	return [dict get $result id]
    }

    #----------------------------------------------------------------------------
    #
    # Cleared --
    #
    #	find cleared pages
    #
    # Parameters:
    #
    # Results:
    #	list of matching records
    #
    #----------------------------------------------------------------------------
    proc Cleared {} {
	variable pageV
	return [s2l [$pageV select -min date 1 -max page " " -rsort date] 100]
    }

    #----------------------------------------------------------------------------
    #
    # Cleared --
    #
    #	return all valid pages
    #
    # Parameters:
    #
    # Results:
    #	list of matching records
    #
    #----------------------------------------------------------------------------
    proc AllPages {} {
	variable pageV
	return [s2l [$pageV select -min id 11 -min date 1 -sort date]]
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
	variable pageV

	# Special case for the fake pages

	switch $id {
	    2 - 4 {
		return [list [list 0 [clock seconds]
			      {Version information not maintained for this page}]]
	    }
	}

	# Determine the number of the most recent version
	set results [list]
	set mostRecent [Versions $id]

	# List the most recent version if requested
	if {$start == 0} {
	    GetPageVars $id date who
	    lappend results [list $mostRecent $date $who]
	    incr start
	}

	# Do earlier versions as needed
	set changeV [$pageV open $id changes]
	set idx [expr {$mostRecent - $start}]
	while {$idx >= 0 && [llength $results] < $limit} {
	    lassign [$changeV get $idx date who] date who
	    lappend results [list $idx $date $who]
	    incr idx -1
	}
	$changeV close
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
	variable pageV
	set page [$pageV get $id]
	set latest [Versions $id]
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
	set changeV [$pageV open $id changes]
	while {$v > $version} {
	    incr v -1
	    set i [ChangeSetSize $id $v]
	    set diffV [$changeV open $v diffs]
	    while {$i > 0} {
		incr i -1
		
		dict with [$diffV get $i]
		if {$from <= $to} {
		    set lines [eval [linsert $old 0 \
					 lreplace $lines[set lines {}] $from $to]]
		} else {
		    set lines [eval [linsert $old 0 \
					 linsert $lines[set lines {}] $from]]
		}
	    }
	    $diffV close
	}
	$changeV close
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
	variable pageV
	set latest [Versions $id]
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
	set changeV [$pageV open $id changes]

	# Start the annotation by guessing that all lines have been there since
	# the first commit of the page.

	if {$version == $latest} {
	    GetPageVars $id date who
	} else {
	    lassign [$changeV get $version date who] date who
	}
	if {$latest == 0} {
	    set firstdate $date
	    set firstwho $who
	} else {
	    lassign [$changeV get 0 date who] firstdate firstwho
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
	    set i [ChangeSetSize $id $version]
	    lassign [$changeV get $version date who] lastdate lastwho
	    set diffV [$changeV open $version diffs]
	    while {$i > 0} {
		incr i -1
		lassign [$diffV get $i from to old] from to old
		
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
	    $diffV close
	    set date $lastdate
	    set who $lastwho
	}
	$changeV close

	set result {}
	foreach line $lines v $versions date $dates who $whos {
	    lappend result [list $line $v $date $who]
	}
	return $result
    }

    # addRefs - a newly created page $id contains $refs references to other pages
    # Add these references to the .ref view.
    proc addRefs {id refs} {
	variable refV
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
	variable refV
	set v [$refV select from $id]	;# the set of all references from $id
	set size [$v size]
	set indices {}
	for {set i 0} {$i < $size} {incr i} {
	    lappend indices [$v get $i index]
	}
	set indices [lsort -integers $indices]

	# delete from last to first
	set n [llength $indices]
	while {[incr n -1] >= 0} {
	    $refV delete [lindex $indices $n]
	}
    }

    # FixPageRefs - recreate the entire refs view
    proc FixPageRefs {} {
	variable refV
	variable pageV

	$refV size 0	;# delete all contents from the .refs view

	# visit each page, recreating its refs
	set size [$pageV size]
	for {set id 0} {$id < $size} {incr id} {
	    GetPageVars $id date page
	    if {$date != 0} {
		# add the references from page $id to .refs view
		addRefs $id [StreamToRefs [TextToStream $page] [list ::WubWikit::InfoProc]]
	    }
	}
	commit
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
	variable pageV

	# Store summary information about the change
	set version [Versions $id]
	set changeV [$pageV open $id changes]
	$changeV insert end date $date who $who
	set diffV [$changeV open $version diffs]

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
	    $diffV insert end from $from to $to old $old
	    incr i
	}

	$changeV set $version delta $change	;# record magnitude of changes
	$changeV close
	$diffV close
    }

    # SavePage - store page $id ($who, $text, $newdate)
    proc SavePage {id text newWho newName {newdate ""} {commit 1}} {
	puts "SavePageDB@[clock seconds] start"

	set changed 0

	if {[catch {
	    puts "SavePageDB@[clock seconds] pagevarsDB"
	    GetPageVars $id name date page who

	    if {$newName != $name} {
		puts "SavePageDB@[clock seconds] new name"
		set changed 1

		# rewrite all pages referencing $id changing old name to new
		# Special case: If the name is being removed, leave references intact;
		# this is used to clean up duplicates.
		if {$newName != ""} {
		    foreach x [ReferencesTo $id] {
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
		$pageV set page $text who $newWho
		if {$page ne {} || [Versions $id]} {
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
	    commit
	}

        puts "SavePageDB@[clock seconds] done."
    }

    proc WikiDatabase {args} {
	variable db wdb
	variable file wikit.db
	variable readonly
	set shared 0
	dict for {n v} $args {
	    set $n $v
	}

	if {[lsearch -exact [mk::file open] $db] == -1} {
	    if {$readonly == -1} {
		if {[file exists $file] && ![file writable $file]} {
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
	    if {[catch {
		mk::file open $db $file -nocommit {*}$flags
	    } msg]
		&& [file $tst $file]
	    } {
		# if we can write and/or read the file but can't open
		# it using mk then it is almost always inside a starkit,
		# so we copy it to memory and open it from there
		set readonly 1
		mk::file open $db
		set fd [open $file]
		mk::file load $db $fd
		close $fd
		set msg ""
	    }

	    if {$msg != "" && ![string equal $msg $db]} {
		error $msg
	    }

	    # open our views
	    variable pageV [mk::view open $db.pages]
	    variable refV [mk::view open $db.refs]

	    # if there are no references, probably it's the first time, so recalc
	    if {!$readonly && [$refV size] == 0} {
		# this can take quite a while, unfortunately - but only once
		FixPageRefs
	    }
	}
    }

    namespace export -clear *
    namespace ensemble create -subcommands {}
}
