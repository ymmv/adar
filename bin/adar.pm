package adar;

use strict;
use warnings;
use Carp;
use Data::Dumper;
use Exporter qw(import);

our @ISA       = qw(Exporter);
our @EXPORT = qw( pnt_open bin_open fdt_open fdt_close
  read_zstring read_lstring read_string read_char
  read_u8 read_u16le read_u16be read_u32le read_u32be
  ddm_read pnt_load pnt_dump ddm_dump fdt_dump
);

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

sub read_string {
    my $fh = shift @_;

    my $text = '';
    while ( read $fh, my $packed_length, 2 ) {
        my $length = unpack 'v', $packed_length;

        read $fh, $text, $length;

        print STDERR $length, "\t", $text, "\n"
          if $DEBUG;
    }
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
    my %dbdesc;

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
            $dbdesc{files}->{$s}->{$p} = $cfg->val( $s, $p );
        }
    }

    # Implant bin and pnt files in %dbdesc for each fdt.
    foreach my $fnr ( keys %{ $dbdesc{files} } ) {
        if ( defined $fnr ) {
            my $basename = $dbdesc{files}->{$fnr}->{fdt};
            $basename =~ s/\.fdt$/.bin/;
            $dbdesc{files}->{$fnr}->{bin_file} = $basename
              if not defined $dbdesc{files}->{$fnr}->{bin_file};
            $basename =~ s/\.bin$/.pnt/;
            $dbdesc{files}->{$fnr}->{pnt_file} = $basename
              if not defined $dbdesc{files}->{$fnr}->{pnt_file};
        }
    }

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
            $dbdesc{ddm_fields}->{$p}->{name}    = $field;
            $dbdesc{ddm_fields}->{$p}->{type}    = $type;
            $dbdesc{ddm_fields}->{$p}->{comment} = $comment if defined $comment;
            $dbdesc{ddm_fields}->{$field}->{type} = $type;
        }
    }
    print Dumper \%dbdesc if $DEBUG;

    return \%dbdesc;
}

my %pnt_method = (
    D => \&read_u32le,
    K => \&read_u32le,
    S => \&read_zstring,
);

#
# pnt file format 
#   index field (could be string (inr), u32le (Duden_F), etc.
#   pointer into bin file (u32le)
#
sub pnt_load {
    my $dbdesc = shift @_;
print Dumper \%pnt_method;

    foreach my $file ( keys %{ $dbdesc->{files} } ) {
        my $filename = $dbdesc->{files}->{$file}->{pnt_file};

        print "-- Reading pnt file $filename\n" if $DEBUG;

        my $fh = pnt_open($filename);

        while ( !eof($fh) ) {
            # Get type of first field, read it from filehandle.
            my $type = $dbdesc->{ddm_fields}->{1}->{type};
            my $method = $pnt_method{$type};
            print Dumper $method;
#            my $key = $pnt_method{ $dbdesc->{ddm_fields}->{1}->{type} }->($fh);
            my $key = $method->($fh);
            my $p   = read_u32le($fh);
print "--pnt-- key-pointer : $key : $p\n";

            $dbdesc->{files}->{$file}->{pnt}->{$key} = $p;
        }

        close $fh or croak "Can't close $filename";

    }

    print Dumper $dbdesc if $DEBUG;
}



sub pnt_dump {
    my $dbdesc = shift @_;

    foreach my $file ( keys %{ $dbdesc->{files} } ) {
        print
          "-- Dumping pnt file $file " . $dbdesc->{files}->{$file}->{pnt_file} ."\n";

        if ( defined( $dbdesc->{files}->{$file}->{pnt} ) ) {

            print "-- Index\n";
            my $deleted    = 0;
            my $prevoffset = 0;
            my $maxlen     = 0;
            my $minlen     = 10000000;

            # 
            # Loop through all possible physical files
            #
            foreach
              my $i ( 0 .. scalar( @{ $dbdesc->{files}->{$file}->{pnt} } ) )
            {
                my $p = $dbdesc->{files}->{$file}->{pnt}->{$i};
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

    my @fn = map { $dbdesc->{files}->{$_}->{fdt} } keys %{ $dbdesc->{files} };

    my $fdt =  $dbdesc->{fdt};

    foreach my $filename (@fn) {
        if ( !-f $filename ) {
            if ( -f $filename . '.fdt' ) {
                $filename = $filename . '.fdt';
            }
        }

        my $fh = fdt_open($filename);

        #
        # Header
        #

        # 8 octets
        #    print read_u8($fh), "\n";

        my $unknown=1;
        print $fdt->{'unknown'.$unknown++} = read_u16le($fh), "\n";
        print $fdt->{'unknown'.$unknown++} =  read_u16le($fh), "\n";
        print $fdt->{number_of_fields} = read_u16le($fh), "\n";
        print $fdt->{'unknown'.$unknown++} = read_u16le($fh), "\n";

        # Nom de fichier de données
        print $fdt->{data_file} = read_zstring($fh), "\n";

        # extension
        print $fdt->{data_extension} = read_zstring($fh), "\n";

        # Nom de fichier d'index
        print $fdt->{index_file} = read_zstring($fh), "\n";

        # extension
        print $fdt->{index_extension} =read_zstring($fh), "\n";

        print "-- 5 champs 16bit\n";
        print $fdt->{'unknown'.$unknown++} = read_u16le($fh), "\n";
        print $fdt->{'unknown'.$unknown++} = read_u16le($fh), "\n";
        print $fdt->{'unknown'.$unknown++} = read_u16le($fh), "\n";
        print $fdt->{'unknown'.$unknown++} = read_u16le($fh), "\n";
        print $fdt->{'unknown'.$unknown++} = read_u16le($fh), "\n";

        # premier champ
        print "-- Premier champ ??\n";
        my $keyfield = read_char($fh) . read_char($fh);
        $fdt->{'key?'} = $keyfield;
        push @{$fdt->{keyfield}}, read_u16le($fh),;
        push @{$fdt->{keyfield}}, read_u16le($fh),;
        push @{$fdt->{keyfield}}, read_u16le($fh),;
        push @{$fdt->{keyfield}}, read_u16le($fh),;
        push @{$fdt->{keyfield}}, read_u16le($fh),;

        # Description des champs
        print "-- Description des champs\n";
        for my $i ( 1 .. $fdt->{number_of_fields} ) {

            # nom du champ (zstring ?)
            my $fieldname = read_zstring($fh);
            push @{$fdt->{$fieldname}}, read_u16le($fh); # field len
            push @{$fdt->{$fieldname}}, read_u16le($fh);
            push @{$fdt->{$fieldname}}, read_u16le($fh);
            push @{$fdt->{$fieldname}}, read_u16le($fh);
            push @{$fdt->{$fieldname}}, read_u16le($fh);
        }

        # informations sur les champs ou index ??
        print "-- Informations sur les champs ou index\n";
        for my $i ( 1 .. $fdt->{number_of_fields} ) {
            print read_u16le($fh),   " ",
              print read_u16le($fh), " ",
              print read_u16le($fh), " ",
              print read_u16le($fh), " ",
              "\n";
        }

        print read_u16le($fh), "\n";

        # Description des colonnes
        print "-- Description des colonnes\n";
        foreach my $i ( 1 .. $fdt->{number_of_fields} ) {
            print read_lstring($fh), "\n";
        }
    }

}

1;

