# Args: db historyDir
#    db - path of the wikit database
#    historyDir - path of the directory containing change history.

# The next few lines are some temporary stuff because I don't have the
# Wub paths set up properly

lappend auto_path [file dirname [file dirname [file normalize [info script]]]]

package require struct::list 1.6.1
package require Mk4tcl
package require Wikit::Db

set dbPath [file normalize [lindex $argv 0]]
set histdir [file normalize [lindex $argv 1]]

Wikit::WikiDatabase $dbPath wdb
Wikit::BuildTitleCache wdb

set workList {}
set fileList [glob -directory $histdir -type file -tails *-*-*]
foreach file $fileList {
    foreach {page date who} [split $file -] break
    lappend worklist [list $date $file]
}

set tick [expr {[clock seconds] + 60}]
foreach tuple [lsort -integer -index 0 $worklist] {
    set file [lindex $tuple 1]
    foreach {id date who} [split $file -] break
    set f [open [file join $histdir $file] r]
    fconfigure $f -encoding utf-8
    # undo incorrect double encoding of the history file
    set data [encoding convertfrom utf-8 [read $f]]
    close $f
    if {[regexp -expanded -- {
	Title:\s*([^\n]*)\n
	Date:\s*([^\n]*)\n
	Site:\s*([^\n]*)\n\n(.*)
    } $data -> name hdate who page]} {
	set lcname [string tolower $name]
	set idShouldBe -1
	if {[info exists Wikit::titleCache(wdb,$lcname)]} {
	    set idShouldBe $Wikit::titleCache(wdb,$lcname)
	} elseif {$id >= [mk::view size wdb.pages]} {
	    mk::view size wdb.pages [expr {$id + 1}]
	}
	if {$idShouldBe == -1} {
	    foreach {dbname dbdate dbwho dbpage} \
		[mk::get wdb.pages!$id name date who page] \
		break
	    set firstref [mk::select wdb.refs -count 1 to $id]
	    if {($dbname ne $name && $dbname ne {})
		&& ($firstref ne {} || $dbpage ne {})} {
		set idShouldBe [Wikit::LookupPage $name]
		puts "file $file ($hdate) creates a new page $idShouldBe because $id was in use for \"$dbname\""
	    } else {
		puts "file $file ($hdate) overrides a previously unused page \"$dbname\""
		set idShouldBe $id
	    }
	}
	if {$idShouldBe != $id} {
	    puts "file $file ($hdate) will be applied to page $idShouldBe (\"$name\") instead of $id"
	}
	set date [clock scan $hdate -format "%d %b %Y %H:%M:%S %Z"]
		  
	Wikit::SavePageDB wdb $idShouldBe $page $who $name $date
	puts "$who updated page $idShouldBe (\"$name\"), version [mk::view size wdb.pages!$id.changes] at $hdate"
	if {[clock seconds] > $tick} {
	    puts "commit"
	    Wikit::DoCommit wdb
	    set tick [expr {[clock seconds] + 60}]
	}
    } else {
	puts "file $file rejected because of malformed data"
	set stop($page) 1
	continue
    }
}
puts "commit at end of load"
Wikit::DoCommit wdb
