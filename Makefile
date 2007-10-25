SRC    = wikit
DEST   = wiki.tcl.tk:~www-data/wikitcl

RSYNC  = rsync -avz --checksum --exclude .svn --exclude .DS_Store --exclude Test.tcl
SCRUB  = | egrep -v '^(building|wrote|total)' | egrep -v '^$$' || true

.PHONY: check install

check:
	@$(RSYNC) --dry-run $(SRC) $(DEST)

prod:
	@$(RSYNC) $(SRC) $(DEST)
