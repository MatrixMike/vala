NULL =

AM_CPPFLAGS = \
	$(GLIB_CFLAGS) \
	$(NULL)

AM_LDFLAGS = \
	$(GLIB_LIBS) \
	$(NULL)

TESTS_ENVIRONMENT = EXEEXT=$(EXEEXT) PACKAGE_SUFFIX=$(PACKAGE_SUFFIX) TOPBUILDDIR=$(abs_top_builddir) TOPSRCDIR=$(abs_top_srcdir) $(srcdir)/testrunner.sh

TESTS = \
	libvaladoc/errorreporter.vala \
	libvaladoc/markupreader.vala \
	libvaladoc/gtkdoc-scanner.vala \
	libvaladoc/parser/manyrule.vala \
	libvaladoc/parser/oneofrule.vala \
	libvaladoc/parser/sequencerule.vala \
	libvaladoc/parser/optionalrule.vala \
	libvaladoc/parser/stubrule.vala \
	$(NULL)

check-TESTS: $(TESTS)
	@EXEEXT=$(EXEEXT) PACKAGE_SUFFIX=$(PACKAGE_SUFFIX) TOPBUILDDIR=$(abs_top_builddir) TOPSRCDIR=$(abs_top_srcdir) $(srcdir)/testrunner.sh $(TESTS)

EXTRA_DIST = \
	testrunner.sh \
	drivers/api-test.data.vapi \
	drivers/generic-api-test.vala \
	libvaladoc/parser/generic-scanner.vala \
	$(TESTS) \
	$(NULL)

