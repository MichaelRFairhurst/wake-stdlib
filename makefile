PROGRAM := wake-js-gen

# set to false or it will be linked with a main()
EXECUTABLE := false
MAINCLASS := Main
MAINMETHOD := "main()"

# Include all wake libraries by default since there aren't many just yet
LIBRARYFILES := $(wildcard lib/obj/*.o)
LIBRARYTABLES := $(wildcard lib/table/*.table)
LIBRARYMODULEFILES := $(wildcard lib/*/obj/*.o)
LIBRARYMODULETABLES := $(wildcard lib/*/table/*.table)


##
# You can edit these directories if you wish
##
SRCDIR := src
TESTDIR := test
GENDIR := gen
TABLEDIR := bin/waketable
OBJECTDIR := bin/wakeobj
SRCDEPDIR := bin/srcdep
TESTDEPDIR := bin/testdep
RUNTESTS := tests

##
# Use command names based on OS
##
ifeq ($(OS),Windows_NT)
	WAKE := wake.exe
	NODE := node.exe
	WUNIT := node.exe wunit-compiler
	WOCKITO := node.exe wockito-generator
	MD5SUM := win/md5sums.exe -u
	WGET := win/wget.exe
	UNZIP := win/tar.exe -xvf
	RMR := $(RM) /s
else
	WAKE := wake
	NODE := node
	WUNIT := node wunit-compiler
	WOCKITO := node wockito-generator
	UNZIP := tar -xvf
	RM := rm -f
	RMR := rm -rf
endif
ifeq ($(shell uname),Linux)
	MD5SUM := md5sum
	WGET := wget
endif
ifeq ($(shell uname),Darwin)
	MD5SUM := md5
	WGET := curl -o libs-latest.tar
endif


##
# Download lib sources if they don't exist
##
ifeq ($(strip $(wildcard lib/*)),)
	FORCESHELL := $(shell $(WGET) http://wakelang.com/libs-latest.tar)
	FORCESHELL := $(shell $(UNZIP) libs-latest.tar)
	FORCESHELL := $(shell $(RM) libs-latest.tar )
	FORCESHELL := $(shell mv bundle lib)
endif


##
# Gather the current code
##
SOURCEFILES := $(wildcard $(SRCDIR)/*.wk) $(wildcard $(SRCDIR)/*/*.wk)
TESTFILES := $(wildcard $(TESTDIR)/*.wk) $(wildcard $(TESTDIR)/*/*.wk)
JSSOURCEFILES := $(wildcard $(SRCDIR)/extern/js/*.wk) $(wildcard $(SRCDIR)/extern/js/*/*.wk)
JSTESTFILES := $(wildcard $(TESTDIR)/extern/js/*.wk) $(wildcard $(TESTDIR)/extern/js/*/*.wk)
#INTERNALSOURCEFILES := $(wildcard $(SRCDIR)/extern/internals/*.wk) $(wildcard $(SRCDIR)/extern/internals/*/*.wk)
#INTERNALJSSOURCEFILES := $(wildcard $(SRCDIR)/extern/internals/*.js) $(wildcard $(SRCDIR)/extern/internals/*/*.js)

##
# Calculate our artifacts
##
DEPFILES := ${SOURCEFILES:$(SRCDIR)/%.wk=$(SRCDEPDIR)/%.d} ${TESTFILES:$(TESTDIR)/%.wk=$(TESTDEPDIR)/%.d} ${JSSOURCEFILES:$(SRCDIR)/extern/js/%.wk=$(SRCDEPDIR)/%.d} ${JSTESTFILES:$(TESTDIR)/extern/js/%.wk=$(TESTDEPDIR)/%.d}
OBJECTFILES := ${SOURCEFILES:$(SRCDIR)/%.wk=$(OBJECTDIR)/%.o}
TESTOBJECTFILES := ${TESTFILES:$(TESTDIR)/%.wk=$(OBJECTDIR)/%.o}
TABLEFILES := ${SOURCEFILES:$(SRCDIR)/%.wk=$(TABLEDIR)/%.table}
TESTTABLEFILES := ${TESTFILES:$(TESTDIR)/%.wk=$(TABLEDIR)/%.table}

JSOBJECTFILES := ${JSSOURCEFILES:$(SRCDIR)/extern/js/%.wk=$(OBJECTDIR)/%.o}
JSTESTOBJECTFILES := ${JSTESTFILES:$(TESTDIR)/extern/js/%.wk=$(OBJECTDIR)/%.o}
JSTABLEFILES := ${JSSOURCEFILES:$(SRCDIR)/extern/js/%.wk=$(TABLEDIR)/%.table}
JSTESTTABLEFILES := ${JSTESTFILES:$(TESTDIR)/extern/js/%.wk=$(TABLEDIR)/%.table}

INTERNALJSOBJECTFILES := ${INTERNALJSSOURCEFILES:$(SRCDIR)/extern/internals/%.js=$(OBJECTDIR)/%.o}
INTERNALTABLEFILES := ${INTERNALSOURCEFILES:$(SRCDIR)/extern/internals/%.wk=$(TABLEDIR)/%.table}


## ENTRY POINT ##
ifeq ($(EXECUTABLE), true)
all: bin/$(PROGRAM)
else
all: package
endif

##
# Include dynamic makefiles generated for each source file
#
# Each source and test file creates a makefile which specifies
# mocks needed, and imported files. This allows wockito to
# generate minimal mocks incrementally, and allows make to
# build sources in the correct order.
##
ifneq "$(MAKECMDGOALS)" "clean"
-include $(DEPFILES)
endif


##
# Calculate the mock artifacts based on what our dynamic
# makefiles counted.
##
MOCKOBJECTFILES := $(subst .table.md5,.o,$(subst $(TABLEDIR),$(OBJECTDIR),$(MOCKS)))
MOCKCLASSNAMES := $(MOCKS:$(TABLEDIR)/%Mock.table.md5=%)
# only link MockProvider if we have at least one mock
ifneq ($(MOCKCLASSNAMES),)
	MOCKPROVIDEROBJ := $(OBJECTDIR)/wkto.gen/MockProvider.o
endif

## Build a package ##
package: $(OBJECTFILES) $(TABLEFILES) $(RUNTESTS) $(JSOBJECTFILES) $(INTERNALJSOBJECTFILES) $(JSTABLEFILES) $(INTERNALTABLEFILES)
	#@echo $(foreach module,$(subst $(OBJECTDIR)/,,$(wildcard $(OBJECTDIR)/*)), \
		#$(shell mkdir bin/packages/$(module)) \
		#$(shell mkdir bin/packages/$(module)/obj) \
		#$(shell mkdir bin/packages/$(module)/table) \
		#$(shell cp $(TABLEDIR)/$(module)/*.table bin/packages/$(module)/table) \
		#$(shell cp $(OBJECTDIR)/$(module)/*.o bin/packages/$(module)/obj))

## Compile our main executable ##
bin/$(PROGRAM): $(OBJECTFILES) $(TABLEFILES) $(LIBRARYFILES) $(LIBRARYMODULEFILES) $(RUNTESTS) $(JSOBJECTFILES) $(INTERNALJSOBJECTFILES) $(JSTABLEFILES) $(INTERNALTABLEFILES)
	$(WAKE) -l -d $(TABLEDIR) $(OBJECTFILES) $(LIBRARYFILES) $(LIBRARYMODULEFILES) $(JSOBJECTFILES) $(INTERNALJSOBJECTFILES) -c $(MAINCLASS) -m $(MAINMETHOD) -o bin/$(PROGRAM)


##
# Run test suite. The test suite is built whenever any source files or
# test files change. Uses wUnit, which uses reflection to generate a
# test suite based on existing tablefiles.
##
.PHONY:
tests: bin/$(PROGRAM)-test
	$(NODE) bin/$(PROGRAM)-test

bin/$(PROGRAM)-test: $(OBJECTFILES) $(TESTLIBRARYFILES) $(LIBRARYFILES) $(LIBRARYMODULEFILES) $(TABLEFILES) $(TESTOBJECTFILES) $(TESTTABLEFILES) $(JSOBJECTFILES) $(JSTESTOBJECTFILES) $(INTERNALJSOBJECTFILES) $(JSTABLEFILES) $(JSTESTTABLEFILES)
	$(WUNIT)
	$(WAKE) bin/TestSuite.wk -d $(TABLEDIR) -o bin/TestSuite.o
	$(WAKE) -l -d $(TABLEDIR) $(OBJECTFILES) $(TESTOBJECTFILES) $(JSOBJECTFILES) $(JSTESTOBJECTFILES) $(INTERNALJSOBJECTFILES) $(TESTLIBRARYFILES) $(LIBRARYFILES) $(LIBRARYMODULEFILES) $(MOCKOBJECTFILES) $(MOCKPROVIDEROBJ) bin/TestSuite.o -o bin/$(PROGRAM)-test -c TestSuite -m 'tests()'


##
# MD5 features. This lets make decide not to rebuild sources that depend
# on other sources which changed, but only when the interface of that source
# also changed.
##
to-md5 = $1 $(addsuffix .md5,$1)

%.md5: % FORCE
	@$(if $(filter-out $(shell cat $@ 2>/dev/null),$(shell $(MD5SUM) $*)),$(MD5SUM) $* > $@)

FORCE:


##
# Copy our library table files into our table dir
##
$(addprefix $(TABLEDIR)/,$(notdir $(LIBRARYTABLES))): $(LIBRARYTABLES)
	cp $(LIBRARYTABLES) $(TABLEDIR)

$(addprefix $(TABLEDIR)/,$(subst /table,,$(subst lib/,,$(LIBRARYMODULETABLES:/table/=)))): $(LIBRARYMODULETABLES)
	@echo $(foreach module,$(filter-out lib/obj lib/table,$(wildcard lib/*)),$(shell mkdir $(TABLEDIR)/$(notdir $(module))) $(shell cp $(wildcard $(module)/table/*) $(TABLEDIR)/$(notdir $(module))))


##
# Generate the dynamic makefiles that determine compilation
# order and mock creation
##
$(SRCDEPDIR)/%.d: $(SRCDIR)/%.wk
	@mkdir $(dir $@) 2>/dev/null || :
	@mkdir $(OBJECTDIR)/$(dir $*) 2>/dev/null || :
	@$(NODE) generate-makefile $< $(TABLEDIR) > $@

$(TESTDEPDIR)/%.d: $(TESTDIR)/%.wk
	@mkdir $(dir $@) 2>/dev/null || :
	@mkdir $(OBJECTDIR)/$(dir $*) 2>/dev/null || :
	@$(NODE) generate-makefile $< $(TABLEDIR) > $@

$(SRCDEPDIR)/%.d: $(SRCDIR)/extern/js/%.wk
	@$(NODE) generate-makefile $< $(TABLEDIR) > $@

$(TESTDEPDIR)/%.d: $(TESTDIR)/extern/js/%.wk
	@$(NODE) generate-makefile $< $(TABLEDIR) > $@


##
# Wake compiler commands
##
$(OBJECTDIR)/%.o: $(SRCDIR)/%.wk
	$(WAKE) $< -d $(TABLEDIR) -o $@

$(OBJECTDIR)/%.o: $(TESTDIR)/%.wk
	$(WAKE) $< -d $(TABLEDIR) -o $@


##
# Don't do anything, but tell make that .table files are created with .o files
##
$(TABLEDIR)/%.table: $(TESTDIR)/%.wk $(OBJECTDIR)/%.o
	@:

$(TABLEDIR)/%.table: $(SRCDIR)/%.wk $(OBJECTDIR)/%.o
	@:


##
# Extern classes need the table file, then are generated by a command named in the directory
##
$(TABLEDIR)/%.table: $(TESTDIR)/extern/js/%.wk
	$(WAKE) $< -d $(TABLEDIR) -t

$(TABLEDIR)/%.table: $(SRCDIR)/extern/js/%.wk
	$(WAKE) $< -d $(TABLEDIR) -t

$(OBJECTDIR)/%.o: $(TABLEDIR)/%.table $(SRCDIR)/extern/js/%.wk
	$(NODE) wake-js-gen $< $@

$(OBJECTDIR)/%.o: $(TABLEDIR)/%.table $(TESTDIR)/extern/js/%.wk
	$(NODE) wake-js-gen $< $@


##
# Internals (for wake std lib only, unless you are brave)
##
$(TABLEDIR)/%.table: $(SRCDIR)/extern/internals/%.wk
	$(WAKE) $< -d $(TABLEDIR) -t

$(OBJECTDIR)/%.o: $(SRCDIR)/extern/internals/%.js
	cat $< | ./js_to_wakeobj.sh > $@

##
# Compile our mocks. This first rule generates a .o file and three
# .table files. The last three rules tell make that the .table files
# are made when the .o file is made.
##
$(OBJECTDIR)/%Mock.o: $(GENDIR)/%Mock.wk
	@mkdir $(dir $@) 2>/dev/null || :
	@mkdir $(OBJECTDIR)/$(dir $*) 2>/dev/null || :
	$(WAKE) $< -d $(TABLEDIR) -o $@

$(TABLEDIR)/%Mock.table: $(GENDIR)/%Mock.wk $(OBJECTDIR)/%Mock.o
	@:

$(TABLEDIR)/%Stubber.table: $(OBJECTDIR)/%Mock.o
	@:

$(TABLEDIR)/%Verifier.table: $(OBJECTDIR)/%Mock.o
	@:

##
# Mock source generation
##
$(GENDIR)/wkto.gen.%Mock.wk: $(TABLEDIR)/%.table.md5
	$(WOCKITO) -d $(TABLEDIR) $(subst /,.,$*) -o $@

$(GENDIR)/wkto.gen/%Mock.wk: $(TABLEDIR)/%.table.md5
	$(WOCKITO) -d $(TABLEDIR) $(subst /,.,$*) -o $@

$(GENDIR)/wkto.gen/MockProvider.wk: $(MOCKS)
	$(WOCKITO) -p -d $(TABLEDIR) $(MOCKCLASSNAMES) -o $@


##
# Mock provider compilation
##
$(OBJECTDIR)/wkto.gen/MockProvider.o: $(GENDIR)/wkto.gen/MockProvider.wk
	@mkdir $(dir $@) 2>/dev/null || :
	@mkdir $(OBJECTDIR)/$(dir $*) 2>/dev/null || :
	$(WAKE) $< -d $(TABLEDIR) -o $@

$(TABLEDIR)/wkto.gen/MockProvider.table: $(OBJECTDIR)/wkto.gen/MockProvider.o


##
# And clean up after our selves. Woo!
##
clean:
	$(RMR) $(TABLEDIR)/* || :
	$(RMR) $(SRCDEPDIR)/* || :
	$(RMR) $(TESTDEPDIR)/* || :
	$(RMR) $(OBJECTDIR)/* || :
	$(RM) bin/TestSuite.wk || :
	$(RM) bin/TestSuite.o || :
	$(RMR) bin/$(PROGRAM) || :
	$(RMR) bin/$(PROGRAM)-test || :
	$(RMR) $(GENDIR)/* || :
	find . -name '*.md5' -delete


##
# This stuff is special to the std lib
##

# use % for . so that make treats all targets as being the result of one command (neat trick)
bin/waketable/lang/Num%table bin/waketable/lang/Text%table bin/waketable/lang/Bool%table bin/waketable/lang/Char%table bin/waketable/lang/Int%table : src/extern/internals/lang/Num%wk src/extern/internals/lang/Text%wk src/extern/internals/lang/Bool%wk src/extern/internals/lang/Char%wk src/extern/internals/lang/Int%wk
	mkdir bin/waketable/lang || :
	$(WAKE) -t $^ -d $(TABLEDIR)

bin/waketable/lang/List.table : bin/waketable/lang/Num.table bin/waketable/lang/Text.table bin/waketable/lang/Bool.table
