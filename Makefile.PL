use inc::Module::Install;
use lib 'lib';

use FindBin;
if(-e "$FindBin::Bin/local-lib") {
    use lib "$FindBin::Bin/local-lib/lib/perl5";
    require local::lib; local::lib->import("$FindBin::Bin/local-lib/perl5/");
}

name 'Thruk';
all_from 'lib/Thruk.pm';

license 'gpl3';
resources(
    'homepage',   => 'http://www.thruk.org',
    'bugtracker'  => 'http://github.com/sni/Thruk/issues',
    'repository', => 'http://github.com/sni/Thruk',
);

requires 'JSON'                                   => 0;     # required by Thruk::View::JSON
requires 'JSON::XS'                               => 0;     # required by Thruk::View::JSON
requires 'Path::Class'                            => 0;     # required by Catalyst::Runtime
requires 'Params::Validate'                       => 0;     # required by Moose
requires 'Config::General'                        => 0;     # required by Thruk::Utils
requires 'Class::Data::Inheritable'               => 0;     # required by Catalyst::Plugin::Thruk::RemoveNastyCharsFromHttpParam
requires 'MRO::Compat'                            => 0;     # required by Catalyst::Plugin::Unicode::Encoding
requires 'File::Copy::Recursive'                  => 0.38;
requires 'Scalar::Util'                           => 1.21;
requires 'List::Util::XS'                         => 0;
requires 'Class::C3::Adopt::NEXT'                 => 0;     # required by Catalyst::View::GD
requires 'URI::Escape'                            => 0;     # required by Thruk::Controller::Root
requires 'Moose'                                  => 0;     # required by Thruk::Action::AddDefaults
requires 'Monitoring::Livestatus'                 => 0.74;
requires 'Monitoring::Livestatus::Class'          => 0.03;
requires 'Monitoring::Availability'               => 0.20;  # required by Thruk::Controller::avail
requires 'GD'                                     => 2.44;  # required by Thruk::Utils::Trends
requires 'Template'                               => 0;     # required by Thruk
requires 'Template::Plugin::Date'                 => 0;     # required by Thruk::Utils
requires 'Date::Calc'                             => 6.3;   # required by Thruk::Utils
requires 'Date::Calc::XS'                         => 0;     # required by Thruk::Utils
requires 'Data::Page'                             => 0;     # required by Thruk::Backend::Manager
requires 'File::Slurp'                            => 0;     # required by Thruk::Utils
requires 'Date::Manip'                            => 0;     # required by Thruk::Utils
requires 'Excel::Template::Plus'                  => 0;     # required by Thruk::Utils
requires 'Class::Accessor::Fast'                  => 0;     # required by Catalyst::Authentication::Credential::Thruk
requires 'Catalyst'                               => 5.80020;
requires 'Catalyst::Runtime'                      => 0;     # required by Thruk
requires 'Catalyst::Controller'                   => 0;     # required by Thruk::Controller::*
requires 'Catalyst::Exception'                    => 0;     # required by Catalyst::View::GD
requires 'Catalyst::Action::RenderView'           => 0;     # required by Thruk
requires 'Catalyst::Authentication::User::Hash'   => 0;     # required by Catalyst::Authentication::Store::FromCGIConf.pm
requires 'Catalyst::View'                         => 0;     # required by Catalyst::View::GD
requires 'Catalyst::View::TT'                     => 0;     # required by Thruk
requires 'Catalyst::View::GD'                     => 0;     # required by Thruk
requires 'Catalyst::View::JSON'                   => 0;     # required by Thruk
requires 'Catalyst::View::Excel::Template::Plus'  => 0;     # required by Thruk::Utils
requires 'Catalyst::Plugin::ConfigLoader'         => 0;     # required by Catalyst::Plugin::Thruk::ConfigLoader
requires 'Catalyst::Plugin::Static::Simple'       => 0;     # required by Thruk
requires 'Catalyst::Plugin::Authorization::Roles' => 0;     # required by Catalyst::Plugin::Authorization::ThrukRoles
requires 'Catalyst::Plugin::CustomErrorMessage'   => 0;     # required by Thruk
requires 'Catalyst::Plugin::Redirect'             => 0;     # required by Thruk
requires 'Catalyst::Plugin::Compress'             => 0;     # required by Thruk
requires 'Catalyst::Plugin::Cache'                => 0;     # required by Thruk
requires 'Log::Log4perl::Catalyst'                => 0;     # required by Thruk
requires 'Catalyst::Engine::FastCGI'              => 0;     # required by Thruk
requires 'FCGI'                                   => 0;     # required by Thruk
requires 'FCGI::ProcManager'                      => 0;     # required by Thruk
requires 'FCGI::ProcManager::MaxRequests'         => 0;     # required by Thruk

# dashboard plugin
feature     ('plugin_dashboard',
  -default                                        => 0,
  'List::Compare'                                 => 0,
  'List::MoreUtils'                               => 0,
);

# requirements test requirements
feature     ('author_test',
  -default                                                                  => 0,
  'Catalyst::Devel'                                                         => 0,
  'Catalyst::Plugin::StackTrace'                                            => 0,
  'HTML::Lint'                                                              => 0,
  'File::BOM'                                                               => 0,
  'Test::Pod'                                                               => 1.40,
  'Test::Perl::Critic'                                                      => 0,
  'Test::Pod::Coverage'                                                     => 0,
  'Perl::Critic::Policy::Dynamic::NoIndirect'                               => 0,
  'Perl::Critic::Policy::NamingConventions::ProhibitMixedCaseSubs'          => 0,
  'Perl::Critic::Policy::ValuesAndExpressions::ProhibitAccessOfPrivateData' => 0,
);

##################################
# should come with Catalyst::Devel
eval {
    catalyst();
};

##################################
# check plugin test symlinks
my $testlinks = {};
mkdir("t/xt") unless -d "t/xt";
for my $testdir (glob('plugins/plugins-enabled/*/t')) {
    $testdir =~ m|/plugins-enabled/(.*)/t|gmx or die("test directory $testdir does not have valid format!");
    my $plugin = $1;

    if(!-e 't/xt/'.$plugin and !-l 't/xt/'.$plugin) {
        symlink('../../plugins/plugins-enabled/'.$plugin.'/t', 't/xt/'.$plugin) or die("cannot create symlink ('../../plugins/plugins-enabled/$plugin/t', 't/xt/$plugin'): $!");
        $testlinks->{$plugin} = '../../plugins/plugins-enabled/'.$plugin.'/t';
        next;
    }
    my $target = readlink('t/xt/'.$plugin);
    if($target ne '../../plugins/plugins-enabled/'.$plugin.'/t') {
        die('t/xt/'.$plugin.' has wrong target: '.$target.' vs. ../../plugins/plugins-enabled/'.$plugin.'/t');
    }
    $testlinks->{$plugin} = $target;
}

# check if there are some links too much
my @cur_t_links = glob('t/xt/*');
for my $link (@cur_t_links) {
    my $target = readlink($link);
    my $linkbasename = $link;
    $linkbasename =~ s/\/\.$//gmx;
    $linkbasename =~ s/^.*\///gmx;
    $link         =~ s/\/\.$//gmx;
    if(!defined $testlinks->{$linkbasename}) {
        unlink($link) or die($link.' should be deleted: '.$!);
    }
    elsif($testlinks->{$linkbasename} ne $target) {
        die($link.' has wrong target: '.$target.' vs. '.$testlinks->{$linkbasename});
    }
}

# cleanup old links
for my $rootlink (glob("./root/thruk/plugins/*")) {
    unlink($rootlink) unless -e $rootlink;
}

# touch the Makefile, so Extutils skips its broken 'check_manifest()'
`touch Makefile`;

tests_recursive;
install_script glob('script/*.pl');
auto_install;
WriteAll;

##################################
# patch our makefile
my $new_makefile = '';
open(my $fh, '<', 'Makefile') or die("cannot open Makefile");
my $found_make_create_distdir = 0;
while(<$fh>) {
    my $line = $_;
    if($line =~ m/^install\s*:/mx) {
        $line = <<EOT;
do_not_install :
	\$(NOECHO) \$(ECHO) make install is not supported.
	\$(NOECHO) \$(ECHO) please have a look at the documentation on howto install Thruk.
	exit 1

install :: do_not_install pure_install doc_install
EOT
    }
    # search the create_distdir part
    if($line =~ m/create_distdir\s*:/mx) {
        $found_make_create_distdir = 1;
    }
    if($found_make_create_distdir and $line =~ m/^\s*$/mx) {
        $found_make_create_distdir = 0;
        my $cp_option;
        $cp_option = "-d" if $^O eq 'linux';
        $cp_option = "-R" if $^O eq 'freebsd';
        $cp_option = "-R" if $^O eq 'darwin';
        $line = "\t".'for file in `cat MANIFEST`; do if [ -d $$file -a -L $$file ]; then $(CP) '.$cp_option.' $$file $(DISTVNAME)/`dirname $$file`/; fi; done'."\n".$line if defined $cp_option;
    }

    # set tests
    if($line =~ m/^TEST_FILES\s*=/mx) {
        $line = "TEST_FILES = t/*.t t/xt/*/*.t\n";
    }
    $new_makefile .= $line;
}
close($fh);
open(my $fh, '>', 'Makefile') or die("cannot open Makefile for writing");
print $fh $new_makefile;
close($fh);
`cat script/append.make >> Makefile`;
print "patched Makefile\n";
print "finished\n";
