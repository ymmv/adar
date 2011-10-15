use Module::Build;
my $build = Module::Build->new(
    module_name  => 'adar',
    version_from => 'lib/adar.pm',
    script_files => 'bin/adar',
    license      => 'perl',
    requires     => {
        'perl' => '5.6.1',    # really ? should check [on] Solaris 8
                              # default perl # version...
        'Carp' => 0,
        'Data::HexDump'       => 0,
    },
    recommends => { 'Test::More' => '0', },
    add_to_cleanup => [ '*~', '*/*~', '*/*/*~', '*/*/*/*~' ],
    gzip           => 'gzip
                                                                                                                         -9f',
);
$build->create_build_script;

