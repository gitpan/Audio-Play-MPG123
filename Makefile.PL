require 5.005;

use ExtUtils::MakeMaker;

WriteMakefile(
    'dist'	=> {
	            PREOP	=> 'chmod -R u=rwX,go=rX . ;',
	            COMPRESS	=> 'gzip -9v',
	            SUFFIX	=> '.gz',
	           },
    'NAME'	=> 'Audio::Play::MPG123',
    'EXE_FILES'	=> ['mpg123sh'],
    'VERSION_FROM' => 'MPG123.pm',
    'LIBS'	=> [''],
    'DEFINE'	=> '',
    'INC'	=> '',
);
