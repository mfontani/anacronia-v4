all: xs test

xs: blib/arch/auto/Av4/Ansi/Ansi.bundle
	@echo Building XS modules..

blib/arch/auto/Av4/Ansi/Ansi.bundle:
	perl Build.PL
	./Build

tidy:
	perl scripts/tidyup.pl

test: xs
	prove --verbose -l lib/ t/

cover:
	cover -delete
	HARNESS_PERL_SWITCHES=-MDevel::Cover make test
	cover

