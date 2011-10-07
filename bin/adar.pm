package adar;

use strict;
use warnings;
use Carp;
use File::Basename;
use Data::Dumper;
use Exporter qw(import);
use Fcntl qw( :DEFAULT :seek );

our @ISA    = qw(Exporter);
our @EXPORT = (
    'pnt_open',     'bin_open',     'fdt_open',     'fdt_close',
    'read_lstring', 'read_zstring', 'read_fstring', 'read_char',
    'read_u8',      'read_u16le',   'read_u16be',   'read_u32le',
    'read_u32be',   'ddm_read',     'pnt_load',     'pnt_dump',
    'ddm_dump',     'fdt_dump',     'fdt_load',
);

sub my_filter {
    my ($hash) = @_;

    # return an array ref containing the hash keys to dump
    # in the order that you want them to be dumped
    return [ ( sort keys %$hash ) ];

}

$Data::Dumper::Sortkeys = \&my_filter;

my $DEBUG;
$DEBUG = 1;

sub pnt_open {
    my $filename = shift @_;

    my $fh;
    open $fh, '<', $filename or croak "Couldn't open file $filename: $!\n";
    binmode $fh;

    return $fh;
}

sub bin_open {
    my $filename = shift @_;

    my $fh;
    open $fh, '<', $filename or croak "Couldn't open file $filename: $!\n";
    binmode $fh;

    return $fh;
}

sub fdt_open {
    my $filename = shift @_;

    my $fh;
    open $fh, '<', $filename or croak "Couldn't open file $filename: $!\n";
    binmode $fh;

    return $fh;
}

sub fdt_close {
    my $fh = shift @_;

    close $fh or croak "Couldn't close file: $!\n";
}

sub pnt_close {
    my $fh = shift @_;

    close $fh or croak "Couldn't close file: $!\n";
}

sub read_zstring {
    my $fh      = shift @_;
    my $content = 0;

    my $text = '';
  ZSTRING:
    while ( read( $fh, $content, 1 ) ) {
        my $c = unpack 'C', $content;
        last ZSTRING if !$c;
        $text .= $content,;
    }

    return $text;
}

sub read_lstring {
    my $fh = shift @_;

    my $l    = read_u16le($fh);
    my $text = read_zstring($fh);

    croak "input not an lstring : length($text) != $l"
      if $l != 1 + length($text);
    return $text;
}

sub read_fstring {
    my ( $fh, $l ) = @_;

    my $text = '';
    read $fh, $text, $l;

    return $text;
}

sub read_char {
    my $fh = shift @_;
    read $fh, my $content, 1;
    return $content;
}

sub read_u8 {
    my $fh = shift @_;
    read $fh, my $content, 1;
    my $val = unpack 'C', $content;
    return $val;
}

sub read_u16le {
    my $fh = shift @_;

    read $fh, my $content, 2;
    my $val = unpack 'v', $content;

    return $val;
}

sub read_u16be {
    my $fh = shift @_;

    read $fh, my $content, 2;
    my $val = unpack 'n', $content;

    return $val;
}

sub read_u32le {
    my $fh = shift @_;

    read $fh, my $content, 4;
    my $val = unpack 'V', $content;

    return $val;
}

sub read_u32be {
    my $fh = shift @_;

    read $fh, my $content, 4;
    my $val = unpack 'V', $content;

    return $val;
}

sub ddm_read {
    my $filename = shift @_;
    my $dbdesc   = {};

    if ( !-f $filename ) {
        if ( -f $filename . '.ddm' ) {
            $filename = $filename . '.ddm';
        }
        else {
            croak "Can't find ddm file $filename";
        }
    }

    my $cfg = Config::IniFiles->new( -file => $filename );

    # FILE* sections
    my @sections = $cfg->Sections;
    print 'Sections ' . Dumper \@sections;
    my @s = grep /^FILE/, @sections;
    print 'FILE Sections ' . Dumper \@s;

    # Feed the {files} subhash with what is present in the ddm, mainly
    # fdt file names
    foreach my $s ( grep /^FILE/, @sections ) {
        foreach my $p ( $cfg->Parameters($s) ) {
            $dbdesc->{files}->{$s}->{$p} = $cfg->val( $s, $p );
        }
    }

    # Implant bin and pnt files in %dbdesc for each fdt.

=pod
    foreach my $fnr ( keys %{ $dbdesc->{files} } ) {
        if ( defined $fnr ) {
            my $basename = $dbdesc->{files}->{$fnr}->{fdt_fields};
            $basename =~ s/\.fdt$/.bin/;
            $dbdesc->{files}->{$fnr}->{bin_file} = $basename
              if not defined $dbdesc->{files}->{$fnr}->{bin_file};
            $basename =~ s/\.bin$/.pnt/;
            $dbdesc->{files}->{$fnr}->{pnt_file} = $basename
              if not defined $dbdesc->{files}->{$fnr}->{pnt_file};
        }
    }
=cut

    # DDF section
    my $count;
    foreach my $p ( $cfg->Parameters('DDF') ) {
        if ( $p eq 'cnt' ) {
            $count = $cfg->val( 'DDF', $p );
        }
        else {
            my $fieldesc = $cfg->val( 'DDF', $p );
            my ( $field, $type, $comment );
            if ( $fieldesc =~ m{ (\w{2}) \s* [,] ([\w]+) \s* (.*) }imxs ) {
                ( $field, $type, $comment ) = ( $1, $2, $3 );
                if ( defined $comment ) {
                    $comment =~ s{ \A \s* [;] \s* }{}imxs;
                }
            }
            $dbdesc->{ddm_fields}->{$p}->{name}    = $field;
            $dbdesc->{ddm_fields}->{$p}->{type}    = $type;
            $dbdesc->{ddm_fields}->{$p}->{comment} = $comment
              if defined $comment;
            $dbdesc->{ddm_fields}->{$field}->{type} = $type;
        }
    }

    #    print Dumper \%dbdesc if $DEBUG;

    return $dbdesc;
}

my %pnt_method = (
    D => \&read_u32le,
    K => \&read_u32le,
    S => \&read_fstring,
);

#
# pnt file format
#   index field (could be string (inr), u32le (Duden_F), etc.
#   pointer into bin file (u32le)
#
sub pnt_load {
    my $dbdesc = shift @_;

    foreach my $file ( keys %{ $dbdesc->{files} } ) {
        my $filename = $dbdesc->{files}->{$file}->{index_file};

        print "-- Reading pnt file $filename\n" if $DEBUG;

        my $fh = pnt_open($filename);

        my $type   = $dbdesc->{ddm_fields}->{1}->{type};
        my $method = $pnt_method{$type};
        print Dumper $method;

        my $keyname   = $dbdesc->{files}->{$file}->{key};
        my $field_len = $dbdesc->{files}->{$file}->{fields}->{$keyname}->{len};

        while ( !eof($fh) ) {

            # Get type of first field, read it from filehandle.
            my $key = $method->( $fh, $field_len );

            # Then read position in data file
            my $p = read_u32le($fh);

            #           print "--pnt-- key-pointer : $key($field_len) : $p\n";

            $dbdesc->{files}->{$file}->{pnt}->{$key} = $p;
        }

        pnt_close($fh);
    }

    #    print Dumper $dbdesc if $DEBUG;
}

sub pnt_dump {
    my $dbdesc = shift @_;

    #
    # Loop through all possible physical files
    #
    foreach my $file ( keys %{ $dbdesc->{files} } ) {
        print "-- Dumping pnt file $file "
          . $dbdesc->{files}->{$file}->{pnt_file} . "\n";

        my $deleted    = 0;
        my $prevoffset = 0;
        my $maxlen     = 0;
        my $minlen     = 10000000;

        my $pnt = $dbdesc->{files}->{$file}->{pnt}; 
        foreach my $i ( sort { $pnt->{$a} <=> $pnt->{$b} }  keys %{$pnt} ) {
            my $p = $pnt->{$i};
            if ( defined $p ) {
                my $len = $p - $prevoffset;
                $maxlen = $len if $len > $maxlen;
                $minlen = $len if $len < $minlen && $len != 0;
                print "$i : $p ($len)\n";

                $prevoffset = $p;
            }
            else {
                $deleted++;
                print "$i : deleted\n";

            }
        }
        print "minlen : $minlen, maxlen = $maxlen, deleted = $deleted\n";
    }

}

sub ddm_dump {
    my $dbdesc = shift @_;

    print Dumper $dbdesc;
}

sub fdt_dump {
    my $dbdesc = shift @_;

    print Dumper $dbdesc;
}

sub fdt_load {
    my $dbdesc = shift @_;

    foreach my $file ( keys %{ $dbdesc->{files} } ) {
        my $filename = $dbdesc->{files}->{$file}->{fdt};

        if ( !-f $filename ) {
            if ( -f $filename . '.fdt' ) {
                $filename = $filename . '.fdt';
            }
        }

        my $fh = fdt_open($filename);

        my $fdt = {};

        #
        # Header
        #

        # 8 octets
        #    print read_u8($fh), "\n";

        my $unknown = 1;
        $dbdesc->{files}->{$file}->{ 'unknown' . $unknown++ } = read_u16le($fh);
        $dbdesc->{files}->{$file}->{ 'unknown' . $unknown++ } = read_u16le($fh);
        $dbdesc->{files}->{$file}->{number_of_fields}         = read_u16le($fh);
        $dbdesc->{files}->{$file}->{ 'unknown' . $unknown++ } = read_u16le($fh);

        #
        # Nom de fichier de données
        #
        $dbdesc->{files}->{$file}->{data_file} = read_zstring($fh);

        #
        # extension
        #
        $dbdesc->{files}->{$file}->{data_extension} = read_zstring($fh);

        #
        # Nom de fichier d'index
        #
        $dbdesc->{files}->{$file}->{index_file} = read_zstring($fh);

        #
        # extension
        #
        $dbdesc->{files}->{$file}->{index_extension} = read_zstring($fh);

        #
        # 5 champs 16bit
        #
        $dbdesc->{files}->{$file}->{ 'unknown' . $unknown++ } = read_u16le($fh);
        $dbdesc->{files}->{$file}->{ 'unknown' . $unknown++ } = read_u16le($fh);
        $dbdesc->{files}->{$file}->{ 'unknown' . $unknown++ } = read_u16le($fh);
        $dbdesc->{files}->{$file}->{ 'unknown' . $unknown++ } = read_u16le($fh);
        $dbdesc->{files}->{$file}->{ 'unknown' . $unknown++ } = read_u16le($fh);

        #
        # First field ? Index key ? Let's say the later
        #
        my $keyfield = read_char($fh) . read_char($fh);
        $dbdesc->{files}->{$file}->{'key'} = $keyfield;
        push @{ $dbdesc->{files}->{$file}->{keyfield} }, read_u16le($fh),;
        push @{ $dbdesc->{files}->{$file}->{keyfield} }, read_u16le($fh),;
        push @{ $dbdesc->{files}->{$file}->{keyfield} }, read_u16le($fh),;
        push @{ $dbdesc->{files}->{$file}->{keyfield} }, read_u16le($fh),;
        push @{ $dbdesc->{files}->{$file}->{keyfield} }, read_u16le($fh),;

        #
        # Description des champs
        #
        for my $i ( 1 .. $dbdesc->{files}->{$file}->{number_of_fields} ) {

            # nom du champ (zstring ?)
            my $fieldname = read_zstring($fh);
            $fdt->{$fieldname}->{len} = read_u16le($fh);    # field len
            push @{ $fdt->{$fieldname}->{info} }, read_u16le($fh);
            push @{ $fdt->{$fieldname}->{info} }, read_u16le($fh);
            push @{ $fdt->{$fieldname}->{info} }, read_u16le($fh);
            push @{ $fdt->{$fieldname}->{info} }, read_u16le($fh);
        }

        #
        # Informations sur les champs ou index ??
        #
        for my $i ( 1 .. $dbdesc->{files}->{$file}->{number_of_fields} ) {
            my $fieldname = $dbdesc->{ddm_fields}->{$i}->{name};

            $fdt->{$fieldname}->{more_info}->{i1} = read_u16le($fh);
            $fdt->{$fieldname}->{more_info}->{i2} = read_u16le($fh);
            $fdt->{$fieldname}->{more_info}->{i3} = read_u16le($fh);
            $fdt->{$fieldname}->{more_info}->{i4} = read_u16le($fh);
        }

        $dbdesc->{files}->{$file}->{ 'unknown' . $unknown++ } = read_u16le($fh),
          "\n";

        # Description des colonnes
        foreach my $i ( 1 .. $dbdesc->{files}->{$file}->{number_of_fields} ) {
            my $fieldname = $dbdesc->{ddm_fields}->{$i}->{name};
            $fdt->{$fieldname}->{desc} = read_lstring($fh);
        }
        $dbdesc->{files}->{$file}->{fields} = $fdt;

        #
        # Are we done on this file ?
        #
        my $cur = tell $fh;

        # set at the end
        seek $fh, 0, SEEK_END;
        my $end = tell $fh;
        carp "Still " . $end - $cur . " bytes to read on $filename"
          if $end != $cur;

        #        close $fh;
    }

    return $dbdesc;
}

1;

