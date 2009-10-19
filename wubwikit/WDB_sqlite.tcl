package require OO
package require tdbc::sqlite3
package provide WDB 1.0
package provide WDB_sqlite 1.0

Debug on WDB 10

if {0} {
    CREATE TABLE pages (
			id INT NOT NULL,
			name TEXT NOT NULL,
			date INT NOT NULL,
			who TEXT NOT NULL,
			PRIMARY KEY (id));

    CREATE TABLE pages_content (
				id INT NOT NULL,
				content TEXT NOT NULL,
				PRIMARY KEY (id),
				FOREIGN KEY (id) REFERENCES pages(id));

    CREATE TABLE changes (
			  id INT NOT NULL,
			  cid INT NOT NULL,
			  date INT NOT NULL,
			  who TEXT NOT NULL,
			  delta TEXT NOT NULL,
			  PRIMARY KEY (id, cid),
			  FOREIGN KEY (id) REFERENCES pages(id));
    
    CREATE TABLE diffs (
			id INT NOT NULL,
			cid INT NOT NULL,
			did INT NOT NULL,
			fromline INT NOT NULL,
			toline INT NOT NULL,	
			old TEXT NOT NULL,
			PRIMARY KEY (id, cid, did),
			FOREIGN KEY (id, cid) REFERENCES changes(id, cid));

    CREATE TABLE refs (
		       fromid INT NOT NULL,
		       toid INT NOT NULL,
		       PRIMARY KEY (fromid, toid),
		       FOREIGN KEY (fromid) references pages(id),
		       FOREIGN KEY (toid) references pages(id));
}

namespace eval WDB {
    variable readonly 0

    proc statement {name} {
	variable statements
	variable db
	if {![info exists statements($name)]} {
	    switch -exact -- $name {
		"changes_for_pid_ge_date"     { set sql {SELECT * FROM changes WHERE id = :pid AND date >= :date ORDER BY date DESC} }
		"changes_for_pid_lt_date"     { set sql {SELECT * FROM changes WHERE id = :pid AND date < :date ORDER BY date DESC} }
		"changes_for_pid_version"     { set sql {SELECT * FROM changes WHERE id = :pid AND cid  = :version} }
		"changes_for_pid_desc"        { set sql {SELECT * FROM changes WHERE id = :pid ORDER BY cid DESC} }
		"changes_for_pid_asc"         { set sql {SELECT * FROM changes WHERE id = :pid ORDER BY cid} }
		"content_for_pid"             { set sql {SELECT * FROM pages_content WHERE id = :pid} }
		"count_changes_for_pid"       { set sql {SELECT COUNT(*) FROM changes WHERE id = :pid} }
		"count_diffs_for_pid_version" { set sql {SELECT COUNT(*) FROM diffs WHERE id = :pid AND cid = :version} }
		"diffs_for_pid_v"             { set sql {SELECT * FROM diffs WHERE id = :id AND cid = :v ORDER BY did DESC} }
		"count_pages"                 { set sql {SELECT COUNT(*) FROM pages} }
		"count_content_for_id"        { set sql {SELECT COUNT(*) FROM pages_content WHERE id = :id} }
		"page_for_name"               { set sql {SELECT * FROM pages WHERE lower(name) = lower(:name)} }
		"page_for_name_glob"          { set sql {SELECT * FROM pages WHERE name GLOB :glob} }
		"page_for_pid"                { set sql {SELECT * FROM pages WHERE id = :pid} }
		"pages_gt_date"               { set sql {SELECT * FROM pages WHERE date > :date ORDER BY date DESC} }
		"refs_to_pid"                 { set sql {SELECT * FROM refs WHERE toid = :pid ORDER BY fromid ASC} }
		"insert_page"                 { set sql {INSERT INTO pages (id, name, date, who) VALUES (:pid, :name, :date, :who)} }
		"insert_change"               { set sql {INSERT INTO changes (id, cid, date, who, delta) VALUES (:id, :version, :date, :who, :change)} }
		"insert_diff"                 { set sql {INSERT INTO diffs (id, cid, did, fromline, toline, old) VALUES (:id, :version, :i, :from, :to, :old)} }
		"insert_ref"                  { set sql {INSERT INTO refs (fromid, toid) VALUES (:id, :x)} }
		"update_change_delta"         { set sql {UPDATE changes SET delta = :change WHERE id = :id AND cid = :version} }
		"delete_refs_for_id"          { set sql {DELETE FROM refs WHERE fromid = :id} }
		"delete_refs"                 { set sql {DELETE FROM refs} }
		"update_page_date_for_id"     { set sql {UPDATE pages SET date = :newdate WHERE id = :id} }
		"update_page_who_for_id"      { set sql {UPDATE pages SET who = :newWho WHERE id = :id} }
		"update_content_for_id"       { set sql {UPDATE pages_content SET content = :text WHERE id = :id} }
		"insert_content"              { set sql {INSERT INTO pages_content (id, content) VALUES (:id, :text)} }
		default { error "Unknown statement '$name'" }
	    }
	    set statements($name) [$db prepare $sql]
	}
	return $statements($name)
    }

    proc close_statements { } {
	variable statements
	foreach {k v} [array ? statements] {
	    $v close
	    unset statements($k)
	}
    }

    proc commit {} {
	variable db
	set now [clock microseconds]
	$db commit
	Debug.WDB {commit: [expr {([clock microseconds] - $now) / 1000000.0}]sec}
    }
    
    proc rollback {} {
	variable db
	$db rollback
    }

    proc StartTransaction { } {
	variable db
	$db begintransaction
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
    proc ReferencesTo {pid} {
	set result {}
	[statement "refs_to_pid"] foreach -as dicts d {
	    lappend result [dict get $d fromid]
	}
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
	set result {}
	[statement "page_for_name_glob"] foreach -as dicts d {
	    lappend result [dict get $d id]
	}
	Debug.WDB {PageGlobName '$glob' -> $result}
	return $result 
    }

    #----------------------------------------------------------------------------
    #
    # Getpage --
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
	set rs [[statement "page_for_pid"] execute]
	$rs nextdict d
	$rs close
	dict set d content [GetContent $pid]
	set result {}
	if {[llength $args] == 1} {
	    set result [dict get? $d [lindex $args 0]]
	} else {
	    foreach n $args {
		lappend result [dict get? $d $n]
	    }
	}
	Debug.WDB {GetPage $pid $args -> ($result)}
	return $result
    }

    #----------------------------------------------------------------------------
    #
    # Getcontent --
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
	set rsc [[statement "content_for_pid"] execute]
	set rsc_next [$rsc nextdict dc]
	$rsc close
	if {$rsc_next} {
	    return [dict get? $dc content]
	} else {
	    return ""
	}
    }

    #----------------------------------------------------------------------------
    #
    # Versions --
    #
    #	return number of non-current versions of a page
    #
    # Parameters:
    #	pid - the page index of the page whose version count we want
    #
    # Results:
    #	an integer representing the number of versions of the page $pid
    #
    #----------------------------------------------------------------------------
    proc Versions {pid} {
	set rs [[statement "count_changes_for_pid"] execute]
	$rs nextdict d
	$rs close
	return [dict get $d "COUNT(*)"]
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
	set rs [[statement "count_pages"] execute]
	$rs nextdict d
	$rs close
	Debug.WDB {PageCount -> [dict get $d "COUNT(*)"]}
	return [dict get $d "COUNT(*)"]
    }

    #----------------------------------------------------------------------------
    #
    # GetChange --
    #
    #	return named fields from a version of a page
    #
    # Parameters:
    #	pid - the page index of the page whose changes we want
    #	version - the page index of the changes whose fields we want
    #	args - a list of field names whose values we want
    #
    # Results:
    #	Returns a list of values corresponding to the field values of those fields
    #
    #----------------------------------------------------------------------------
    proc GetChange {pid version args} {
	set rs [[statement "changes_for_pid_version"] execute]
	set result {}
	if {[$rs nextdict d]} {
	    foreach a $args {
		lappend result [dict get? $d $a]
	    }
	}
	$rs close
	Debug.WDB {GetChange $pid $version $args -> $result}
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
    #	version - the changeset index whose size we want
    #
    # Results:
    #	Returns an integer, being the size of the changeset
    #
    #----------------------------------------------------------------------------
    proc ChangeSetSize {pid version} {
	set rs [[statement "count_diffs_for_pid_version"] execute]
	$rs nextdict d
	$rs close
	Debug.WDB {ChangeSetSize $pid $version -> [dict get $d "COUNT(*)"]}
	return [dict get $d "COUNT(*)"]
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
    #	Returns The change record of the most recent change
    #
    #----------------------------------------------------------------------------
    proc MostRecentChange {pid date} {
	set rs [[statement "changes_for_pid_lt_date"] execute]
	set result 0
	if {[$rs nextdict d]} {
	    set result [dict get $d cid]
	}
	$rs close
	Debug.WDB {MostRecentChange $pid $date -> $result}
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
	set result {}
	[statement "pages_gt_date"] foreach -as dicts d {
	    lappend result [list id [dict get? $d id] name [dict get? $d name] date [dict get? $d date] who [dict get? $d who]]
	    if {[llength  $result] >= 100} {
		break
	    }
	}
	return $result
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
	set result {}
	[statement "changes_for_pid_ge_date"] foreach -as dicts d {
	    lappend result [list version [dict get? $d cid] date [dict get? $d date] who [dict get? $d who] delta [dict get? $d delta]]
	}
	return $result
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
    #	max - maximum number of records
    #
    # Results:
    #	Returns a list of matching records
    #
    #----------------------------------------------------------------------------
    proc Search {key long date max} {
	variable db

	set fields name
	set stmttxt "SELECT a.id, a.name, a.date FROM pages a, pages_content b WHERE a.id > 11 AND b.id > 11 AND a.id = b.id AND length(a.name) > 0 AND length(b.content) > 1"
	if {$long} {
	    foreach k [split $key " "] {
		append stmttxt " AND (lower(a.name) GLOB lower(\"*$k*\") OR lower(b.content) GLOB lower(\"*$k*\"))"
	    }
	} else {
	    foreach k [split $key " "] {
		append stmttxt " AND lower(a.name) GLOB lower(\"*$k*\")"
	    }
	}
	if {$date > 0} {
	    append stmttxt " AND a.date >= $date"
	} else {
	    append stmttxt " AND a.date > 0"
	}
	append stmttxt " ORDER BY a.date DESC"
	set stmt [$db prepare $stmttxt]
	set rs [$stmt execute]
	set results {}
	set n 0
	while {$n < $max && [$rs nextdict d]} {
	    puts "Search: $d"
	    lappend results [list id [dict get $d id] name [dict get $d name] date [dict get $d date]]
	    incr n
	}
	$rs close
	$stmt close

	Debug.WDB {Search '$key' $long $date -> $results}

	return $results
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
	set date 0
	set who ""
	set lcname [string tolower $name]
	variable namecache
	if {[info exists namecache($lcname)]} {
	    Debug.WDB {LookupPage '$name' found in cache -> $namecache($lcname)}
	    return $namecache($lcname)
	}
	set rs [[statement "page_for_name"] execute]
	set rs_next [$rs nextdict d]
	$rs close
	if {!$rs_next} {
	    set pid [PageCount]
	    Debug.WDB {LookupPage '$name' not found, added $pid}
	    StartTransaction
	    if {[catch {[statement "insert_page"] execute} msg]} {
		rollback
		error $msg
	    } else {
		commit
	    }
	} else {
	    set pid [dict get $d id]
	}
	Debug.WDB {LookupPage '$name' -> $pid}
	set namecache($lcname) $pid
	return $pid
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
	set result {}
	[statement "page_for_name"] foreach -as dicts d {
	    lappend result [dict get $d id]
	}
	Debug.WDB {PageByName '$name' -> $result}
	return $result
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
	set n 0
	set result {}
	set select [$pageV select -rsort date]
	for {set i 0} {$i < [$select size]} {incr i} {
	    lassign [$select get $i id date] id date
	    set cont [GetContent $id]
	    if {[string length $content] <= 1} {
		lappend result [$select get $i]
		incr n
		if {$n>= 100} {
		    break
		}
	    }
	}
	$select close
	return $result
    }

    #----------------------------------------------------------------------------
    #
    # AllPages --
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
	set result {}
	[statement "pages_gt_date"] foreach -as dicts d {
	    lappend result [list id [dict get? $d id] name [dict get? $d name] date [dict get? $d date] who [dict get? $d who]]
	}
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

    proc ListPageVersionsDB {pid {limit Inf} {start 0}} {

	# Special case for the fake pages
	switch $pid {
	    2 - 4 {
		return [list [list 0 [clock seconds]
			      {Version information not maintained for this page}]]
	    }
	}

	# Determine the number of the most recent version
	set results [list]
	set mostRecent [Versions $pid]
	set nskip 0
	set nsel 0

	# List the most recent version if requested
	if {$start == 0} {
	    lassign [GetPage $pid date who] date who
	    lappend results [list $mostRecent $date $who]
	    incr start
	    incr nsel
	    incr nskip
	}
	# select changes pertinent to this page
	[statement "changes_for_pid_desc"] foreach -as dicts d {
	    incr nskip
	    if {$nskip <= $start} {
		continue
	    }
	    lappend results [list [dict get? $d cid] [dict get? $d date] [dict get? $d who]]
	    incr nsel
	    if {$nsel >= $limit} {
		break
	    }
	}
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
	Debug.WDB {GetPageVersion $id $version}
	return [join [GetPageVersionLines $id $version] \n]
    }
    proc GetPageVersionLines {id {rversion {}}} {
	variable db

	Debug.WDB {GetPageVersionLines $id $rversion}
	set content [GetContent $id]
	set latest [Versions $id]
	if {$rversion eq {}} {
	    set rversion $latest
	}
	if {![string is integer $rversion] || $rversion < 0} {
	    error "bad version number \"$rversion\": must be a positive integer"
	}
	if {$rversion > $latest} {
	    error "cannot get version $rversion, latest is $latest"
	}
	if {$rversion == $latest} {
	    # the required version is the latest - just return content
	    return [split $content \n]
	}

	# an earlier version is required
	set v $latest
	set lines [split $content \n]

	while {$v > $rversion} {
	    incr v -1
	    [statement "diffs_for_pid_v"] foreach -as dicts d {
		dict with d {
		    if {$fromline <= $toline} {
			set lines [lreplace $lines[set lines {}] $fromline $toline {*}$old]
		    } else {
			set lines [linsert $lines[set lines {}] $fromline {*}$old]
		    }
		}
	    }
	}

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

    proc AnnotatePageVersion {pid {version {}}} {
	variable db

	set latest [Versions $pid]
	if {$version eq {}} {
	    set version $latest
	}
	if {![string is integer $version] || $version < 0} {
	    error "bad version number \"$version\": must be a positive integer"
	}
	if {$version > $latest} {
	    error "cannot get version $version, latest is $latest"
	}

	# Retrieve the version to be annotated
	set lines [GetPageVersionLines $pid $version]
	set crsdl {}
	[statement "changes_for_pid_asc"] foreach -as dicts d {
	    lappend crsdl $d
	}

	# Start the annotation by guessing that all lines have been there since
	# the first commit of the page.

	if {$version == $latest} {
	    lassign [GetPage $pid date who] date who
	} else {
	    set d [lindex $crsdl $version]
	    set date [dict get? $d date]
	    set who [dict get? $d who]
	}
	if {$latest == 0} {
	    set firstdate $date
	    set firstwho $who
	} else {
	    set d [lindex $crsdl 0]
	    set firstdate [dict get? $d date]
	    set firstwho [dict get? $d who]
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
	    set d [lindex $crsdl $version]
	    set lastdate [dict get? $d date]
	    set lastwho [dict get? $d who]

	    set v $version
	    [statement "diffs_for_pid_v"] foreach -as dicts dd {

		set from [dict get $dd fromline]
		set to [dict get $dd toline]
		set old [dict get $dd old]
		
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
	    set date $lastdate
	    set who $lastwho
	}

	set result {}
	foreach line $lines v $versions date $dates who $whos {
	    lappend result [list $line $v $date $who]
	}

	return $result
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
	set version [Versions $id]
	set change 0	;# record magnitude of change

	# Determine the changed lines
	set linesnew [split $text \n]
	set linesold [split $page \n]

	set lcs [::struct::list longestCommonSubsequence2 $linesnew $linesold 5]
	set changes [::struct::list lcsInvert \
			 $lcs [llength $linesnew] [llength $linesold]]

	# Store change information in the database
	[statement "insert_change"] execute

	set i 0
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
	    [statement "insert_diff"] execute
	    incr i
	}

	[statement "update_change_delta"] execute
    }

    # addRefs - a newly created page $id contains $refs references to other pages
    # Add these references to the .ref view.
    proc addRefs {id refs} {
	if {$id != 2 && $id != 4} {
	    foreach x $refs {
		if {$id != $x} {
		    [statement "insert_ref"] execute
		}
	    }
	}
    }
    
    # delRefs - remove all references from page $id to anywhere
    proc delRefs {id} {
	[statement "delete_refs_for_id"] execute
    }

    # FixPageRefs - recreate the entire refs view
    proc FixPageRefs {} {

	# delete all contents from the .refs view
	[statement "delete_refs"] execute

	# visit each page, recreating its refs
	set size [PageCount]
	StartTransaction
	if {[catch {
	    for {set id 0} {$id < $size} {incr id} {
		set date [GetPage $id date]
		set page [GetContent $id]
		if {$date != 0 && $name ne ""} {
		    # add the references from page $id to .refs view
		    addRefs $id [WFormat StreamToRefs [WFormat TextToStream $page] [list ::WikitWub::InfoProc]]
		}
	    }} msg]} {
	    rollback
	    error $msg
	} else {
	    commit
	}
    }

    # SavePage - store page $id ($who, $text, $newdate)
    proc SavePage {id text newWho newName {newdate ""} {commit 1}} {
	variable db
	puts "SavePage@[clock seconds] start"

	set changed 0

	StartTransaction

	if {[catch {
	    puts "SavePage@[clock seconds] pagevarsDB"
	    lassign [GetPage $id name date who] name date who
	    set page [GetContent $id]

	    # Update of page names not possible using Web interface, placed in comments because untested.
	    #
	    # 	    if {$newName != $name} {
	    # 		puts "SavePage@[clock seconds] new name"
	    # 		set changed 1
	    #
	    # 		# rewrite all pages referencing $id changing old name to new
	    # 		# Special case: If the name is being removed, leave references intact;
	    # 		# this is used to clean up duplicates.
	    # 		if {$newName != ""} {
	    # 		    foreach x [ReferencesTo $id] {
	    # 			set y [$pageV get $x page]
	    # 			$pageV set $x page [replaceLink $y $name $newName]
	    # 		    }
	    #		    
	    # 		    # don't forget to adjust links in this page itself
	    # 		    set text [replaceLink $text $name $newName]
	    # 		}
	    #
	    # 		$pageV set $id name $newName
	    # 	    }

	    if {$newdate != ""} {
		puts "SavePage@[clock seconds] set date $id $date"
		# change the date if requested
		[statement "update_page_date_for_id"] execute
	    }

	    # avoid creating a log entry and committing if nothing changed
	    set text [string trimright $text]
	    if {$changed || $text != $page} {
		puts "SavePage@[clock seconds] parse"
		# make sure it parses before deleting old references
		set newRefs [WFormat StreamToRefs [WFormat TextToStream $text] ::WikitWub::InfoProc]
		puts "SavePage@[clock seconds] delRefs"
		delRefs $id
		puts "SavePage@[clock seconds] addRefs"
		addRefs $id $newRefs

		# If this isn't the first time that the given page has been stored
		# in the databse, make a change log entry for rollback.

		puts "SavePage@[clock seconds] log change"
		[statement "update_page_who_for_id"] execute

		puts "SavePage@[clock seconds] save content"
		set rsc [[statement "count_content_for_id"] execute]
		$rsc nextdict d
		if {[dict get $d COUNT(*)]} {
		    [statement "update_content_for_id"] execute
		} else {
		    [statement "insert_content"] execute
		}
		$rsc close
		puts "SavePage@[clock seconds] saved content"
		if {$page ne {} || [Versions $id]} {
		    puts "SavePage@[clock seconds] update change log (old: [string length $page], [llength [split $page \n]], new:  [string length $text], [llength [split $text \n]])"
		    UpdateChangeLog $id $name $date $who $page $text
		}

		# Set change date, only if page was actually changed
		if {$newdate == ""} {
		    puts "SavePage@[clock seconds] set date"
		    set date [clock seconds]
		    [statement "update_page_date_for_id"] execute
		    set commit 1
		}

		puts "SavePage@[clock seconds] done saving"
	    }
	} r]} {
	    rollback
	    Debug.error "SavePageDb: '$r'"
	    error $r
	}

	if {$commit} {
	    puts "SavePage@[clock seconds] commit"
	    commit
	}

	puts "SavePage@[clock seconds] done."
    }

    proc WikiDatabase {args} {
	variable db wdb
	variable file wikit.db
	dict for {n v} $args {
	    set $n $v
	}
	tdbc::sqlite3::connection create $db $file 
    }

    namespace export -clear *
    namespace ensemble create -subcommands {}
}
