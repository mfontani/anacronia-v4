all: test

tidy:
	perl scripts/tidyup.pl

test:
	prove --verbose -l lib/ t/

cover:
	cover -delete
	HARNESS_PERL_SWITCHES=-MDevel::Cover make test
	cover

