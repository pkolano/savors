-include Makefile.config

all: cloud 

install: prefix all lib_install man_install
	install perl/savors.pl $(PREFIX)bin/savors
	install perl/savors-data perl/savors-view $(PREFIX)bin
	if [ `whoami` = "root" ]; then install -m 0644 etc/savorsrc /etc; fi
	if [ `whoami` != "root" ]; then install -m 0644 etc/savorsrc ~/.savorsrc; fi

clean:
	cd lib/cloud; make clean

distclean: clean
	rm -f Makefile.config

prefix:
	install -d $(PREFIX)bin
	install -d $(PREFIX)lib/savors
	install -d $(PREFIX)man/man1
	install -d $(PREFIX)man/man5
	install -d $(PREFIX)man/man7

cloud:
	cd lib/cloud; make

lib_install: prefix cloud_install map_install perl_install
	install -m 0644 lib/DejaVuSansCondensed.ttf $(PREFIX)lib/savors
	test -z $(GEODB) || test -e $(PREFIX)lib/savors/IP2LOCATION-LITE-DB11.BIN || ln -s $(GEODB) $(PREFIX)lib/savors/geoip.db

cloud_install:
	install -d $(PREFIX)lib/savors/cloud
	install lib/cloud/query_integral_image*.[sd]* $(PREFIX)lib/savors/cloud
	install lib/cloud/wordcloud.py $(PREFIX)lib/savors/cloud

man_install: prefix
	install -m 0644 doc/*.1 $(PREFIX)man/man1
	install -m 0644 doc/*.5 $(PREFIX)man/man5
	install -m 0644 doc/*.7 $(PREFIX)man/man7

map_install:
	install -d $(PREFIX)lib/savors/maps/us_county
	install -d $(PREFIX)lib/savors/maps/us_state
	install -d $(PREFIX)lib/savors/maps/world
	install -m 0644 lib/maps/us_county/* $(PREFIX)lib/savors/maps/us_county
	install -m 0644 lib/maps/us_state/* $(PREFIX)lib/savors/maps/us_state
	install -m 0644 lib/maps/world/* $(PREFIX)lib/savors/maps/world

perl_install:
	install -d $(PLPREFIX)Savors/Console
	install -d $(PLPREFIX)Savors/View
	install -m 0644 perl/Savors/*.pm $(PLPREFIX)Savors
	install -m 0644 perl/Savors/Console/*.pm $(PLPREFIX)Savors/Console
	install -m 0644 perl/Savors/View/*.pm $(PLPREFIX)Savors/View
