# attempt to repair a db by traversing the db history dir and 
package require Mk4tcl
package require fileutil

set dbf [lindex $argv 0]
set histdir [lindex $argv 1]

foreach f [glob -tails -directory $histdir -type file *-*-*] {
    lassign [split $f -] id date who
    if {![info exists diffs($id)]
        || $date > [lindex $diffs($id) 0]
    } {
        set diffs($id) [list $date $id $who $f]
    }
}

mk::file open db $dbf
set max [mk::view size db.pages]

foreach id [lsort -integer [array names diffs]] {
    #lappend repairs [lindex $diffs($id) 1]
    lassign $diffs($id) date id1 who f
    set content [fileutil::cat -encoding utf-8 [file join $histdir $f]]
    # undo incorrect double encoding of the history file
    set content [encoding convertfrom utf-8 $content]
    set content [split $content \n]
    set title [lindex $content 0]
    set content [join [lrange $content 4 end] \n]
    if {$id >= $max} {
        set title [string trim [lindex [split $title :] 1]]
        puts "adding $id '$title'"
        mk::row append db.pages name $title page $content date $date who $who
	incr max
    } else {
	set d [mk::get db.pages!$id date]
	if {$d < $date} {
	    puts "modding $id"
	    mk::set db.pages!$id page $content date $date who $who
	} else {
	    puts "not modding $id - stored version newer."
	}
    }
}

mk::file commit db
mk::file close db
