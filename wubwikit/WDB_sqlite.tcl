package require sqlite3
package require tdbc::sqlite3
package provide WDB 1.0
package provide WDB_sqlite 1.0

if {0} {

    # Compile sqlite with the following defines:
    #
    # -DSQLITE_ENABLE_FTS4
    # -DSQLITE_ENABLE_FTS3_PARENTHESIS


    PRAGMA foreign_keys = ON;
    PRAGMA journal_mode = WAL;

    CREATE TABLE pages (
       id INT NOT NULL,
       name TEXT NOT NULL,
       date INT NOT NULL,
       who TEXT NOT NULL,
       type TEXT,
       PRIMARY KEY (id));
    CREATE INDEX idx_pages_date ON pages(date)

    CREATE TABLE pages_content (
       id INT NOT NULL,
       content TEXT NOT NULL,
       PRIMARY KEY (id),
       FOREIGN KEY (id) REFERENCES pages(id));

    CREATE VIRTUAL TABLE pages_content_fts USING fts4(id,name,content);
    # Insert data into FTS table: insert into pages_content_fts (id, name, content) select a.id, a.name, b.content from pages a, pages_content b where a.id = b.id;

    CREATE TABLE pages_binary (
       id INT NOT NULL,
       content BLOB NOT NULL,
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

    CREATE TABLE changes_binary (
       id INT NOT NULL,
       cid INT NOT NULL,
       date INT NOT NULL,
       who TEXT NOT NULL,
       type TEXT,
       content BLOB NOT NULL,
       PRIMARY KEY (id, cid),
       FOREIGN KEY (id) REFERENCES pages(id));

    CREATE TABLE refs (
       fromid INT NOT NULL,
       toid INT NOT NULL,
       PRIMARY KEY (fromid, toid),
       FOREIGN KEY (fromid) references pages(id),
       FOREIGN KEY (toid) references pages(id));
    CREATE INDEX refs_toid_index ON refs (toid);
}

namespace eval WDB {
    variable readonly 0
    variable transaction_started 0
    variable broken_link_db_available 0
    variable broken_link_cache

    proc statement {name} {
	variable statements
	variable db
	if {![info exists statements($name)]} {
	    switch -exact -- $name {
		"binary_for_pid"                        { set sql {SELECT a.type, b.content FROM pages a, pages_binary b WHERE a.id = :pid AND a.id = b.id} }
		"binary_for_pid_version"                { set sql {SELECT * FROM changes_binary WHERE id = :pid AND cid = :version} }
		"changes_binary_for_pid_desc"           { set sql {SELECT cid, date, who FROM changes_binary WHERE id = :pid ORDER BY cid DESC LIMIT :limit OFFSET :start} }
		"changes_for_pid_asc"                   { set sql {SELECT * FROM changes WHERE id = :pid ORDER BY cid} }
		"changes_for_pid_desc"                  { set sql {SELECT cid, date, who FROM changes WHERE id = :pid ORDER BY cid DESC LIMIT :limit OFFSET :start} }
		"changes_for_pid_ge_date"               { set sql {SELECT * FROM changes WHERE id = :pid ORDER BY date DESC} }
		"changes_for_pid_lt_date"               { set sql {SELECT * FROM changes WHERE id = :pid AND date < :date ORDER BY date DESC} }
		"changes_for_pid_version"               { set sql {SELECT * FROM changes WHERE id = :pid AND cid  = :version} }
		"content_for_pid"                       { set sql {SELECT * FROM pages_content WHERE id = :pid} }
		"count_binary_for_id"                   { set sql {SELECT COUNT(*) FROM pages_binary WHERE id = :id} }
		"count_changes_binary_for_pid"          { set sql {SELECT COUNT(*) FROM changes_binary WHERE id = :pid} }
		"count_changes_for_pid"                 { set sql {SELECT COUNT(*) FROM changes WHERE id = :pid} }
		"count_content_for_id"                  { set sql {SELECT COUNT(*) FROM pages_content WHERE id = :id} }
		"count_diffs_for_pid_version"           { set sql {SELECT COUNT(*) FROM diffs WHERE id = :pid AND cid = :version} }
		"count_pages"                           { set sql {SELECT COUNT(*) FROM pages} }
		"delete_changes_for_pid_version"        { set sql {DELETE FROM changes WHERE id = :pid AND cid = :cid} }
		"delete_changes"                        { set sql {DELETE FROM changes WHERE id = :id} }
		"delete_changes_binary"                 { set sql {DELETE FROM changes_binary WHERE id = :id} }
		"delete_changes_binary_for_pid_version" { set sql {DELETE FROM changes_binary WHERE id = :pid AND cid = :cid} }
		"delete_diffs"                          { set sql {DELETE FROM diffs WHERE id = :id} }
		"delete_diffs_for_pid_version"          { set sql {DELETE FROM diffs WHERE id = :pid AND cid = :cid} }
		"delete_pages_binary"                   { set sql {DELETE FROM pages_binary WHERE id = :id} }
		"delete_pages_content"                  { set sql {DELETE FROM pages_content WHERE id = :id} }
		"delete_refs"                           { set sql {DELETE FROM refs} }
		"delete_refs_from_id"                   { set sql {DELETE FROM refs WHERE fromid = :id} }
		"delete_refs_to_id"                     { set sql {DELETE FROM refs WHERE toid = :id} }
		"diffs_for_pid"                         { set sql {SELECT * FROM diffs WHERE id = :pid} }
		"diffs_for_pid_v"                       { set sql {SELECT fromline, toline, old FROM diffs WHERE id = :pid AND cid = :v ORDER BY did DESC} }
		"insert_binary"                         { set sql {INSERT INTO pages_binary (id, content) VALUES (:id, :text)} }
		"insert_change"                         { set sql {INSERT INTO changes (id, cid, date, who, delta) VALUES (:id, :version, :date, :who, :change)} }
		"insert_change_binary"                  { set sql {INSERT INTO changes_binary (id, cid, date, who, type, content) VALUES (:id, :version, :date, :who, :type, :change)} }
		"insert_content"                        { set sql {INSERT INTO pages_content (id, content) VALUES (:id, :text)} }
		"insert_content_fts"                    { set sql {INSERT INTO pages_content_fts (id, name, content) VALUES (:id, :name, :text)} }
		"insert_diff"                           { set sql {INSERT INTO diffs (id, cid, did, fromline, toline, old) VALUES (:id, :version, :i, :from, :to, :old)} }
		"insert_page"                           { set sql {INSERT INTO pages (id, name, date, who, type) VALUES (:pid, :name, :date, :who, :type)} }
		"insert_ref"                            { set sql {INSERT INTO refs (fromid, toid) VALUES (:id, :x)} }
		"page_for_name"                         { set sql {SELECT * FROM pages WHERE lower(name) = lower(:name)} }
		"page_for_name_glob"                    { set sql {SELECT * FROM pages WHERE name GLOB :glob} }
		"page_for_pid"                          { set sql {SELECT * FROM pages WHERE id = :pid} }
		"pages_gt_date_with_content"            { set sql {SELECT * 
		                                                   FROM pages a, pages_content b 
		                                                   WHERE a.id = b.id 
		                                                   AND a.date > :date 
                                                                   AND length(b.content) > 1
                                                                   ORDER BY a.date DESC
		                                                   LIMIT 100} }
		"binary_gt_date_with_content"           { set sql {SELECT * 
		                                                   FROM pages a, pages_binary b 
		                                                   WHERE a.id = b.id 
		                                                   AND a.date > :date
                                                                   ORDER BY a.date DESC
		                                                   LIMIT 100} }
		"pages_gt_date"                         { set sql {SELECT * FROM pages WHERE date > :date ORDER BY id} }
		"refs_to_pid"                           { set sql {SELECT fromid FROM refs WHERE toid = :pid ORDER BY fromid ASC} }
		"update_change_delta"                   { set sql {UPDATE changes SET delta = :change WHERE id = :id AND cid = :version} }
		"update_content_for_id"                 { set sql {UPDATE pages_content SET content = :text WHERE id = :id} }
		"update_content_fts_for_id"             { set sql {UPDATE pages_content_fts SET content = :text WHERE id = :id} }
		"update_page_date_for_id"               { set sql {UPDATE pages SET date = :newdate WHERE id = :id} }
		"update_page_who_for_id"                { set sql {UPDATE pages SET who = :newWho WHERE id = :id} }
		"update_page_type_for_id"               { set sql {UPDATE pages SET type = :newType WHERE id = :id} }
		"update_binary"                         { set sql {UPDATE pages_binary SET content = :text WHERE id = :id} }
		"enable_foreign_keys"                   { set sql {PRAGMA foreign_keys = ON} }
		"enable_journal_mode_WAL"               { set sql {PRAGMA journal_mode = WAL} }
		"cleared_pages"                         { set sql {SELECT a.id, a.name, a.date, a.who 
		                                                   FROM pages a, pages_content b 
                                                                   WHERE a.id = b.id AND a.date > 0 AND length(b.content) <= 1 
                                                                   ORDER BY a.date DESC LIMIT 100} }
		"redirects_to"                          { set sql {SELECT id
		                                                   FROM pages_content
		                                                   WHERE lower(content) = lower(:redir)} }
		"names"                                 { set sql {SELECT id, name FROM pages} }
		default { error "Unknown statement '$name'" }
	    }
	    set statements($name) [$db prepare $sql]
	}
	return $statements($name)
    }
    proc lstatement {name} {
	variable lstatements
	variable ldb
	if {![info exists lstatements($name)]} {
	    switch -exact -- $name {
		"links" { set sql {SELECT url, status_code FROM link} }
		"broken_links" { set sql {SELECT a.url, a.status_code, b.page FROM link a, link_usage b WHERE a.url = b.url AND (a.status_code < 0 OR a.status_code >= 400)} }
		default { error "Unknown statement '$name'" }
	    }
	    set lstatements($name) [$ldb prepare $sql]
	}
	return $lstatements($name)
    }
    proc pagecache_statement {name} {
	variable pagecache_statements
	variable db
	if {![info exists statements($name)]} {
	    switch -exact -- $name {
		"create" { set sql  {CREATE TABLE pagecache (id INT NOT NULL, content TEXT NOT NULL, ct TEXT NOT NULL, cwhen INT NOT NULL, title TEXT NOT NULL, PRIMARY KEY (id))} }
		"insert" { set sql {INSERT INTO pagecache (id, content, ct, cwhen, title) VALUES (:id, :content, :ct, :when, :title)} }
		"exists" { set sql {SELECT COUNT(*) FROM pagecache WHERE id = :id} }
		"fetch"  { set sql {SELECT * FROM pagecache WHERE id = :id} }
		"delete" { set sql {DELETE FROM pagecache WHERE id = :id} }
		"clear"  { set sql {DELETE FROM pagecache} }
		default  { error "Unknown statement '$name'" }
	    }
	    set pagecache_statements($name) [$db.pagecache prepare $sql]
	}
	return $pagecache_statements($name)
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
	variable transaction_started 0
	set now [clock microseconds]
	$db commit
	Debug.WDB {commit: [expr {([clock microseconds] - $now) / 1000000.0}]sec}
    }
    
    proc rollback {} {
	variable db
	variable transaction_started 0
	$db rollback
    }

    proc StartTransaction { } {
	variable db
	variable transaction_started
	if {!$transaction_started} {
	    $db begintransaction
	    set transaction_started 1
	}
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
	[statement "refs_to_pid"] foreach -as lists d {
	    lappend result {*}$d
	}
	return $result
    }

    proc RedirectsTo {name} {
	set result {}
	set redir "<<redirect>>$name"
	[statement "redirects_to"] foreach -as lists d {
	    lappend result {*}$d
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
	set rsn [$rs nextdict d]
	$rs close
	#dict set d content [GetContent $pid]
	set result {}
	if {$rsn} {
	    if {[llength $args] == 1} {
		set result [dict get? $d [lindex $args 0]]
	    } else {
		foreach n $args {
		    lappend result [dict get? $d $n]
		}
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
    # Getbinary --
    #
    #	return binary page content, with version V is V >= 0, else most recent
    #
    # Parameters:
    #	pid - the page index of the page whose content we want
    #
    # Results:
    #	the binary content of a page and the type
    #
    #----------------------------------------------------------------------------
    proc GetBinary {pid {version -1}} {
	if {![string is integer $version]} {
	    error "bad version number \"$version\": must be a integer"
	}
	set latest [VersionsBinary $pid]
	if {$version > $latest} {
	    error "cannot get version $version, latest is $latest"
	}
	if {$version < 0 || $version == $latest} {
	    set rsc [[statement "binary_for_pid"] execute]
	    set rsc_next [$rsc nextdict dc]
	    $rsc close
	    if {$rsc_next} {
		return [list [dict get? $dc content] [dict get? $dc type]]
	    } else {
		return ""
	    }
	} else {
	    set rsc [[statement "binary_for_pid_version"] execute]
	    set rsc_next [$rsc nextdict dc]
	    $rsc close
	    if {$rsc_next} {
		return [list [dict get? $dc content] [dict get? $dc type]]
	    } else {
		return ""
	    }
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
    proc VersionsBinary {pid} {
	set rs [[statement "count_changes_binary_for_pid"] execute]
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
	[statement "pages_gt_date_with_content"] foreach -as dicts d {
	    if {[dict get? $d type] eq "" || [dict get? $d type] eq "text/x-wikit"} {
		lappend result [list id [dict get? $d id] name [dict get? $d name] date [dict get? $d date] who [dict get? $d who] type [dict get? $d type]]
		if {[llength  $result] >= 100} {
		    break
		}
	    }
	}
	[statement "binary_gt_date_with_content"] foreach -as dicts d {
	    if {[dict get? $d type] ne "" && [dict get? $d type] ne "text/x-wikit"} {
		lappend result [list id [dict get? $d id] name [dict get? $d name] date [dict get? $d date] who [dict get? $d who] type [dict get? $d type]]
		if {[llength  $result] >= 200} {
		    break
		}
	    }
	}
	return [lrange [lsort -integer -decreasing -index 5 $result] 0 100]
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
	    lappend result [list version [dict get $d cid] date [dict get $d date] who [dict get $d who] delta [dict get $d delta]]
	    if {[dict get $d date] < $date} {
		break
	    }
	}
	return $result
    }

    #----------------------------------------------------------------------------
    #
    # RunUserQuery --
    #
    #   run a user query
    #
    # Parameters: 
    #   query - the query to run
    #
    # Results:
    #	Returns a list of matching records
    #
    #----------------------------------------------------------------------------

    proc RunUserQuery {query} {
	variable db
	set results {}
	$db foreach -as dicts d $query {
	    lappend results $d
	}
	return $results
    }

    # LinkBelievedBroken --
    #
    #  check if a link is believed to be broken
    #
    # Parameters:
    #  url - the link
    #
    # Results:
    #  boolean, true is link is broken, false otherwise

    proc LinkBelievedBroken {url} {
	variable broken_link_db_available
	variable broken_link_cache
	if {$broken_link_db_available} {
	    set rt [info exists broken_link_cache($url)]
	} else {
	    set rt 0
	}
	return $rt
    }

    proc BrokenLinks {} {
	variable broken_link_db_available
	set rl {}
	if {$broken_link_db_available} {
	    [lstatement "broken_links"] foreach -as dicts d {
		lappend rl $d
	    }
	}
	return $rl
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

    proc LookupPage {name {query_only 0}} {
	set date 0
	set who ""
	set lcname [string tolower $name]
	variable namecache
	variable transaction_started
	if {[info exists namecache($lcname)]} {
	    Debug.WDB {LookupPage '$name' found in cache -> $namecache($lcname)}
	    return $namecache($lcname)
	}
	set rs [[statement "page_for_name"] execute]
	set rs_next [$rs nextdict d]
	$rs close
	if {!$rs_next} {
	    if {$query_only} {
		return ""
	    } else {
		set pid [PageCount]
		Debug.WDB {LookupPage '$name' not found, added $pid}
		set ts $transaction_started
		if {!$ts} {
		    StartTransaction
		}
		if {[catch {[statement "insert_page"] allrows} msg]} {
		    rollback
		    error $msg
		} else {
		    if {!$ts} {
			commit
		    }
		}
		set transaction_started $ts
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
	set result {}
	[statement "cleared_pages"] foreach -as dicts d {
	    lappend result $d
	}
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
	set date 0
	[statement "pages_gt_date"] foreach -as dicts d {
	    lappend result [list id [dict get $d id] name [dict get $d name] date [dict get $d date] who [dict get $d who]]
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

    proc ListPageVersions {pid {limit -1} {start 0}} {

	# Determine the number of the most recent version
	set results [list]

	# List the most recent version if requested
	if {$start == 0} {
	    lappend results [list [Versions $pid] {*}[GetPage $pid date who]]
	    incr limit -1
	} else {
	    incr start -1
	}
	# select changes pertinent to this page
	[statement "changes_for_pid_desc"] foreach -as lists d {
	    lappend results $d
	}
	return $results
    }

    proc ListPageVersionsBinary {pid {limit -1} {start 0}} {

	# Determine the number of the most recent version
	set results [list]

	# List the most recent version if requested
	if {$start == 0} {
	    lappend results [list [VersionsBinary $pid] {*}[GetPage $pid date who]]
	    incr limit -1
	} else {
	    incr start -1
	}
	# select changes pertinent to this page
	[statement "changes_binary_for_pid_desc"] foreach -as lists d {
	    lappend results $d
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
    proc GetPageVersionLines {pid {rversion {}}} {
	variable db

	Debug.WDB {GetPageVersionLines $pid $rversion}
	set content [GetContent $pid]
	set latest [Versions $pid]
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
		set old [dict get? $dd old]
		
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

		set m1s [struct::list repeat [llength $old] -1]
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
	[statement "insert_change"] allrows

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
	    [statement "insert_diff"] allrows
	    incr i
	}

	[statement "update_change_delta"] allrows
    }

    # addRefs - a newly created page $id contains $refs references to other pages
    # Add these references to the .ref view.
    proc addRefs {id refs} {
	if {$id != 2 && $id != 4} {
	    foreach x $refs {
		if {$id != $x} {
		    [statement "insert_ref"] allrows
		}
	    }
	}
    }
    
    # delRefs - remove all references from page $id to anywhere
    proc delRefs {id} {
	[statement "delete_refs_from_id"] allrows
    }

    # FixPageRefs - recreate the entire refs view
    proc FixPageRefs {} {

	# delete all contents from the .refs view
	[statement "delete_refs"] allrows

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

    # RenamePage
    proc RenamePage {N M newName newdate newWho newType oldName oldDate oldWho oldType} {
	StartTransaction
	if {[catch {
	    # Copy content of $N to $M, keep nick, type and date from old page
	    set oldText [WDB GetContent $N]
	    WDB SavePage $M $oldText $oldWho $oldName $oldType $oldDate 0 0
	    # Copy history of $N to $M
	    set id $M
	    [statement "delete_changes"] allrows
	    [statement "delete_diffs"] allrows
	    set pid $N
	    [statement "changes_for_pid_asc"] foreach -as dicts d {
		set id $M
		set version [dict get $d cid]
		set date [dict get $d date]
		set who [dict get $d who]
		set change [dict get $d delta]
		[statement "insert_change"] allrows
	    }
	    set pid $N
	    [statement "diffs_for_pid"] foreach -as dicts d {
		set id $M
		set version [dict get $d cid]
		set i [dict get $d did]
		set from [dict get $d fromline]
		set to [dict get $d toline]
		set old [dict get $d old]
		[statement "insert_diff"] allrows
	    }
	    # Replace page $N with redirect to $M
	    WDB SavePage $N "<<redirect>>$newName" $newWho $newName $newType [clock seconds] 0 0
	} r eo]} {
	    rollback
	    Debug.error {RenamePage: '$r' ($eo)}
	    error $r
	}
	commit
    }

    # SavePage - store page $id ($who, $text, $newdate)
    proc SavePage {id text newWho newName newType {newdate ""} {commit 1} {use_transaction 1}} {
	variable db
	Debug.WDB {start}

	set changed 0

	if {$use_transaction} {
	    StartTransaction
	}

	if {[catch {
	    Debug.WDB {pagevarsDB}
	    lassign [GetPage $id name date who type] name date who type

	    # Update of page names not possible using Web interface, placed in comments because untested.
	    #
	    # 	    if {$newName != $name} {
	    # 		Debug.WDB {new name}
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

	    # avoid creating a log entry and committing if nothing changed
	    if {$newType eq "" || [string match text/* $newType]} {
		Debug.WDB {text page '$newType'/'$type'}

		if {$newdate != ""} {
		    Debug.WDB {set date $id $date}
		    # change the date if requested
		    [statement "update_page_date_for_id"] allrows
		}

		set text [string trimright $text]
		set page [GetContent $id]
		if {$changed || $text != $page} {
		    Debug.WDB {parse}
		    # make sure it parses before deleting old references
		    set newRefs [::WikitWub::GetRefs $text] ;#[WFormat StreamToRefs [WFormat TextToStream $text] ::WikitWub::InfoProc]
		    Debug.WDB {delRefs}
		    delRefs $id
		    Debug.WDB {addRefs $newRefs}
		    addRefs $id $newRefs

		    # If this isn't the first time that the given page has been stored
		    # in the databse, make a change log entry for rollback.

		    Debug.WDB {log change}
		    [statement "update_page_who_for_id"] allrows

		    Debug.WDB {save content}
		    set rsc [[statement "count_content_for_id"] execute]

		    $rsc nextdict d
		    $rsc close
		    if {[dict get $d COUNT(*)]} {
			[statement "update_content_for_id"] allrows
			[statement "update_content_fts_for_id"] execute
		    } else {
			[statement "insert_content"] allrows
			[statement "insert_content_fts"] execute
		    }
		    Debug.WDB {saved content}
		    if {$page ne {} || [Versions $id]} {
			Debug.WDB {update change log (old: [string length $page], [llength [split $page \n]], new:  [string length $text], [llength [split $text \n]])}
			UpdateChangeLog $id $name $date $who $page $text
		    }

		    if {$newType ne "" && $newType ne $type} {
			[statement update_page_type_for_id] allrows
		    }

		    # Set change date, only if page was actually changed
		    if {$newdate == ""} {
			Debug.WDB {set date}
			set date [clock seconds]
			[statement "update_page_date_for_id"] allrows
			set commit 1
		    }
		    
		    Debug.WDB {done saving}
		}
	    } else {
		# must be binary content
		lassign [GetBinary $id] change
		set rsc [[statement "count_binary_for_id"] execute]
		$rsc nextdict d
		$rsc close
		if {[dict get $d COUNT(*)]} {
		    Debug.WDB {update binary content $type->$newType}
		    [statement update_binary] allrows
		} else {
		    Debug.WDB {insert binary content $type->$newType}
		    [statement insert_binary] allrows
		}
		set version [VersionsBinary $id]
		Debug.WDB {insert binary content version = $version, change size = [string length $change], }
		if {$change ne {} || $version} {
		    [statement insert_change_binary] allrows
		}
		set date [clock seconds]
		[statement update_page_date_for_id] allrows
		[statement update_page_who_for_id] allrows
		[statement update_page_type_for_id] allrows
		Debug.WDB {saved binary content $newType}
	    }
	} r eo]} {
	    if {$use_transaction} {
		rollback
		Debug.error {SavePageDb: '$r' ($eo)}
		error $r
	    }
	}

	if {$use_transaction} {
	    if {$commit} {
		Debug.WDB {commit}
		commit
	    } else {
		Debug.WDB {rollback}
		rollback
	    }
	}

	Debug.WDB {done.}
    }

    proc pagecache {cmd args} {
	variable db
	variable file
	switch -exact -- $cmd {
	    create {
		Debug.WDB {Create pagecache}
		if {[file exists $file.pagecache]} {
		    file delete -force $file.pagecache
		}
		tdbc::sqlite3::connection create $db.pagecache $file.pagecache
		[pagecache_statement "create"] allrows
	    }
	    insert {
		lassign $args id content ct when title
		Debug.WDB {Insert pagecache $id}
		[pagecache_statement "insert"] allrows
	    }
	    exists {
		lassign $args id
		Debug.WDB {Exists pagecache $id}
		set rs [[pagecache_statement "exists"] execute]
		set rsn [$rs nextdict d]
		set n 0
		if {$rsn} {
		    set n [dict get $d "COUNT(*)"]
		}
		$rs close
		return $n
	    }
	    fetch {
		lassign $args id
		Debug.WDB {Fetch pagecache $id}
		set rs [[pagecache_statement "fetch"] execute]
		set d [dict create]
		$rs nextdict d
		$rs close
		return $d
	    }
	    delete {
		lassign $args id
		Debug.WDB {Delete pagecache $id}
		[pagecache_statement "delete"] allrows
	    }
	    clear {
		Debug.WDB {Delete clear}
		[pagecache_statement "clear"] allrows
	    }
	}
    }

    proc WikiDatabase {args} {
	variable db wdb
	variable file wikit.db
	dict for {n v} $args {
	    set $n $v
	}
	Debug.WDB {Opening sqlite3 tdbc at $db $file}
	tdbc::sqlite3::connection create $db $file
	[statement "enable_foreign_keys"] allrows
	[statement "enable_journal_mode_WAL"] allrows
    }

    proc CloseWikiDatabase {} {
	variable db
	variable statements
	puts "Closing Wiki database"
	if {[info exists statements]} {
	    foreach {k v} [array get statements] {
		$v close
	    }
	    unset statements
	    }
	$db close
	unset db
    }

    proc LinkDatabase {args} {
	variable ldb wldb
	variable broken_link_db_available
	variable broken_link_cache
	dict for {n v} $args {
	    set $n $v
	}
	tdbc::sqlite3::connection create $ldb $file
	[statement "enable_foreign_keys"] allrows
	[statement "enable_journal_mode_WAL"] allrows
	unset -nocomplain broken_link_cache
	[lstatement "links"] foreach -as dicts d {
	    set stat [dict get $d status_code]
	    if {$stat < -1 || $stat >= 400} {
		set broken_link_cache([dict get $d url]) 1
	    }
	}
	set broken_link_db_available 1
    }

    proc CloseLinkDatabase {} {
	variable ldb
	variable broken_link_db_available
	variable broken_link_cache
	variable lstatements
	puts "Closing Link database"
	if {$broken_link_db_available} {
	    set broken_link_db_available 0
	    unset -nocomplain broken_link_cache
	    if {[info exists lstatements]} {
		foreach {k v} [array get lstatements] {
		    $v close
		}
		unset lstatements
	    }
	    $ldb close
	}
    }

    proc PrimePagenameCache {} {
	variable namecache
	[statement "names"] foreach -as dicts d {
	    set namecache([string tolower [dict get $d name]]) [dict get $d id]
	}
    }

    namespace export -clear *
    namespace ensemble create -subcommands {}
}
