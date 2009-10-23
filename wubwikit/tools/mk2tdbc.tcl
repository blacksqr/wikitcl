if {[llength $argv] != 2} {
    puts stderr "Usage: mk2tdbc <mkdatabase> <sqlitedatabase>"
    exit 1
}

package require Mk4tcl
package require tdbc::sqlite3

# Open 'old' mk database
mk::file open mdb [lindex $argv 0]
puts [mk::view layout mdb.pages]
puts [mk::view layout mdb.refs]

# Creat new 'sqlite' database
tdbc::sqlite3::connection create sb [lindex $argv 1]

set s [sb prepare {CREATE TABLE pages (
       id INT NOT NULL,
       name TEXT NOT NULL,
       date INT NOT NULL,
       who TEXT NOT NULL,
       PRIMARY KEY (id))}]
$s execute
$s close

set s [sb prepare {CREATE TABLE pages_content (
       id INT NOT NULL,
       content TEXT NOT NULL,
       PRIMARY KEY (id),
       FOREIGN KEY (id) REFERENCES pages(id))}]
$s execute
$s close

set s [sb prepare {CREATE TABLE changes (
       id INT NOT NULL,
       cid INT NOT NULL,
       date INT NOT NULL,
       who TEXT NOT NULL,
       delta TEXT NOT NULL,
       PRIMARY KEY (id, cid),
       FOREIGN KEY (id) REFERENCES pages(id))}]
$s execute
$s close
       
set s [sb prepare {CREATE TABLE diffs (
       id INT NOT NULL,
       cid INT NOT NULL,
       did INT NOT NULL,
       fromline INT NOT NULL,
       toline INT NOT NULL,	
       old TEXT NOT NULL,
       PRIMARY KEY (id, cid, did),
       FOREIGN KEY (id, cid) REFERENCES changes(id, cid))}]
$s execute
$s close

set s [sb prepare {CREATE TABLE refs (
       fromid INT NOT NULL,
       toid INT NOT NULL,
       PRIMARY KEY (fromid, toid),
       FOREIGN KEY (fromid) references pages(id),
       FOREIGN KEY (toid) references pages(id))}]
$s execute
$s close

set s [sb prepare {CREATE INDEX refs_toid_index ON refs (toid)}]
$s execute
$s close

set s [sb prepare {PRAGMA foreign_keys = ON}]
$s execute
$s close

# Prepare required statements
set ipages [sb prepare {INSERT INTO pages VALUES (:p, :p_name, :p_date, :p_who)}]
set ipages_content [sb prepare {INSERT INTO pages_content VALUES (:p, :p_page)}]
set ichanges [sb prepare {INSERT INTO changes VALUES (:p, :c, :c_date, :c_who, :c_delta)}]
set idiffs [sb prepare {INSERT INTO diffs VALUES (:p, :c, :d, :d_from, :d_to, :d_old)}]
set irefs [sb prepare {INSERT INTO refs VALUES (:r_from, :r_to)}]

# Copy the data
for {set p 0} {$p < [mk::view size mdb.pages]} {incr p} {

    lassign [mk::get mdb.pages!$p name page date who] p_name p_page p_date p_who
    puts "$p: $p_name"
    [$ipages execute] close
    [$ipages_content execute] close

    for {set c 0} {$c < [mk::view size mdb.pages!$p.changes]} {incr c} {

	lassign [mk::get mdb.pages!$p.changes!$c date who delta] c_date c_who c_delta
	[$ichanges execute] close

	for {set d 0} {$d < [mk::view size mdb.pages!$p.changes!$c.diffs]} {incr d} {
	    lassign [mk::get mdb.pages!$p.changes!$c.diffs!$d from to old] d_from d_to d_old
	    [$idiffs execute] close
	}
    }
}

for {set r 0} {$r < [mk::view size mdb.refs]} {incr r} {
    lassign [mk::get mdb.refs!$r from to] r_from r_to
    [$irefs execute] close
}

# Cleanup
$ipages close
$ipages_content close
$ichanges close
$idiffs close
$irefs close

mk::file close mdb
sdb close
