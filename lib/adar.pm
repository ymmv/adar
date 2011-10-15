package adar;
use strict;
use warnings;

=head1 NAME

adar - Read and dump pseudo-Adabas content files found in PET & EKTA

=head1 VERSION

This is version 0.01

=cut

my $VERSION = '0.01';

=head1 SYNOPSIS

  use adar;
  my $dbdesc = ddm_read($f);
  ddm_dump($dbdesc);
  fdt_load($dbdesc);
  fdt_dump($dbdesc);
  pnt_load($dbdesc);
  pnt_dump($dbdesc);
  bin_dump($dbdesc);

=head1 DESCRIPTION

TODO

=head1 SUBROUTINES/METHODS

=cut

#use encoding 'iso-8859-1', STDOUT => "utf-8";
use English qw( -no_match_vars );
use Encode qw( :all );
use Carp;
use File::Basename;
use Data::Dumper;
use Data::HexDump;
use Exporter qw(import);
use Fcntl qw( :DEFAULT :seek );

our @ISA    = qw(Exporter);
our @EXPORT = qw(
  read_lstring read_zstring read_fstring read_char
  read_u8      read_u16le   read_u16be   read_u32le
  read_u32be   ddm_read     pnt_load     pnt_dump
  ddm_dump     fdt_dump     fdt_load     bin_dump
);

sub my_filter {
    my ($hash) = @_;

    # return an array ref containing the hash keys to dump
    # in the order that you want them to be dumped
    return [ ( sort keys %{$hash} ) ];

}

my %data_method = (
    D => \&read_u32le,
    S => \&read_lstring,
    K => \&read_lkstring,
    I => \&read_u16le,
    B => \&read_u8,
);

$Data::Dumper::Sortkeys = \&my_filter;

our $DEBUG;

sub read_zstring {
    my ($fh) = @_;
    my $content = 0;

    my $text = q();
  ZSTRING:
    while ( read( $fh, $content, 1 ) ) {
        my $c = unpack 'C', $content;
        last ZSTRING if !$c;
        $text .= $content;
    }

    return $text;
}

sub read_lkstring {
    my ($fh) = @_;

    my $l = read_u8($fh);
    my $text = read_fstring( $fh, $l );

    return $text;
}

sub read_lstring {
    my ($fh) = @_;

    my $l = read_u16le($fh);
    my $text = read_fstring( $fh, $l );

    # Chop trailing \0 if any
    if ( ord( substr( $text, -1, 1 ) ) == 0 ) {
        chop $text;
    }

    return $text;
}

sub read_fstring {
    my ( $fh, $l ) = @_;

    my $text = q();
    read $fh, $text, $l;

    return $text;
}

sub read_char {
    my ($fh) = @_;
    read $fh, my $content, 1;
    return $content;
}

sub read_u8 {
    my ($fh) = @_;
    read $fh, my $content, 1;
    my $val = unpack 'C', $content;
    return $val;
}

sub read_u16le {
    my ($fh) = @_;

    read $fh, my $content, 2;
    my $val = unpack 'v', $content;

    return $val;
}

sub read_u16be {
    my ($fh) = @_;

    read $fh, my $content, 2;
    my $val = unpack 'n', $content;

    return $val;
}

sub read_u32le {
    my ($fh) = @_;

    read $fh, my $content, 4;
    my $val = unpack 'V', $content;

    return $val;
}

sub read_u32be {
    my ($fh) = @_;

    read $fh, my $content, 4;
    my $val = unpack 'V', $content;

    return $val;
}

=head1 C<DDM> file format

A DDF file can have multiple sections :

=head2 C<[VARIABLE]>

This C<VARIABLE> section defines variables inside the DDM file. These
variables will be substituted when enclosed in C<%%>, such as C<%A0%>.

Reference : L<http://pardubickykuryr.eu/etka/DATA/SE/Z_FPreis.ddf>

=head2 C<FILE[\d]+>

When it exists (not in all DDF files), it does define the list of all
FDT files with the same format carrying the data.
FDT files are then pointers to real data.

=over 2

=item * fdt=filename.fdt

FDT file.

=item * ddf=filename.ddf

DDF file, when not described inside the DDM file.

=item * gcx=filename.ddf

GCX (FIXME : field grouping information?) when not defined inside the
DDM file.

=item * buflen=\d+

Size of buffer to read FDT ? BIN file ?

=back

=head2 C<DDF> : Data Definition

This section, present when no C<ddf> key is present from the C<FILE>
section, will help define data and type.

It holds field name, type, and can see VARIABLE expansion. Format
seems pretty relaxed, with either number as a key, or directly field
name. FIXME: Reading it in sequence seems to be better, as we can have
variable names as keys, and will not help for field order. We may have
to switch to customer .ini file reading module to get order (currently
using L<Config::IniFiles>).

When the field number is present, it represent an index in the field
definition table (FDT file).

=over 2

=item * cnt=\d+ : number of fields in the file

=item * {?:\d+|[\w\d]+}=fieldname,format ([A-Z])

Short version (usually spotted directly in DDM file).

=item * {?:\d+|[\w\d]+}=fieldname,key,format ([1|2|4|5|6]),duden ([0|1]),string terminieren([0|1])

Long version (usually spotted directly in a DDF file referenced by a
DDM file).

=back

=head2 Key

1 if field is a key, 0 otherwise.

=head2 Field format (types)

=over 2

=item *

1|S : String

NUL terminated string.

=item *

2|I : Integer

16 bit little endian integer.

=item *

4|D : Long

32 bit little endian integer.

=item *

5|B : Byte

=item *

6|K : Kurzer String (short string).

Not a NUL terminated it seems (FIXME, to check and test with FDT
binary fields if I can find some examples), one will need field length
(from FDT file) to read it.

=back

=head2 duden

1 for true, 0 otherwise. But, FIXME, what is duden ???

=head2 String terminieren

1 for true, 0 otherwise.

=cut

sub ddm_read {
    my ($filename) = @_;
    my $dbdesc = {};

    croak "undefined file name" if not defined $filename;
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
    if ($DEBUG) {
        print 'Sections ' . Dumper \@sections;
    }
    my @s = grep { m{ \A FILE }mxs } @sections;

    if ($DEBUG) {
        print 'FILE Sections ' . Dumper \@s;
    }

    # Feed the {files} subhash with what is present in the ddm, mainly
    # fdt file names
    foreach my $s ( grep { m{ \A FILE }mxs } @sections ) {
        foreach my $p ( $cfg->Parameters($s) ) {
            $dbdesc->{files}->{$s}->{$p} = $cfg->val( $s, $p );
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
            $dbdesc->{ddm_fields}->{$p}->{name} = $field;
            $dbdesc->{ddm_fields}->{$p}->{type} = $type;
            if ( defined $comment ) {
                $dbdesc->{ddm_fields}->{$p}->{comment} = $comment;
            }
            $dbdesc->{ddm_fields}->{$field}->{type} = $type;
        }
    }

    return $dbdesc;
}

=head2 pnt_load

Load pointer file.

PNT file format : 2 fields per record.

=over 4

=item * index field

Could be string (inr), u32le (Duden_F), etc.

=item * pointer into bin file

u32le

=back

=cut

sub pnt_load {
    my ($dbdesc) = @_;

    foreach my $file ( keys %{ $dbdesc->{files} } ) {
        my $filename = $dbdesc->{files}->{$file}->{index_file};

        if ($DEBUG) {
            print "-- Reading pnt file $filename\n";
        }

        my $fh;
        if ( !open $fh, '<', $filename ) {
            croak "Couldn't open file $filename: $ERRNO\n";
        }
        binmode $fh;

        my $type   = $dbdesc->{ddm_fields}->{1}->{type};
        my $method = $data_method{$type};

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

        if ( !close($fh) ) {
            croak "Cannot close $filename";
        }
    }

    #    print Dumper $dbdesc if $DEBUG;
    return $dbdesc;
}

sub pnt_dump {
    my ($dbdesc) = @_;

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
        foreach my $i ( sort { $pnt->{$a} <=> $pnt->{$b} } keys %{$pnt} ) {
            my $p = $pnt->{$i};
            if ( defined $p ) {
                my $len = $p - $prevoffset;

                if ( $len > $maxlen ) {
                    $maxlen = $len;
                }
                if ( $len < $minlen && $len != 0 ) {
                    $minlen = $len;
                }

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

    return $dbdesc;
}

sub ddm_dump {
    my ($dbdesc) = @_;

    print Dumper $dbdesc;

    return $dbdesc;
}

sub fdt_dump {
    my ($dbdesc) = @_;

    print Dumper $dbdesc;

    return $dbdesc;
}

=head2 fdt_load

Read & load FDT information from the FDT file

=cut

sub fdt_load {
    my ($dbdesc) = @_;

    foreach my $file ( keys %{ $dbdesc->{files} } ) {
        my $filename = $dbdesc->{files}->{$file}->{fdt};

        if ( !-f $filename ) {
            if ( -f $filename . '.fdt' ) {
                $filename = $filename . '.fdt';
            }
        }

        my $fh;
        if ( !open $fh, '<', $filename ) {
            croak "Couldn't open file $filename: $ERRNO\n";
        }
        binmode $fh;

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
        # data filename
        #
        $dbdesc->{files}->{$file}->{data_file} = read_zstring($fh);

        #
        # extension
        #
        $dbdesc->{files}->{$file}->{data_extension} = read_zstring($fh);

        #
        # Index filename
        #
        $dbdesc->{files}->{$file}->{index_file} = read_zstring($fh);

        #
        # extension
        #
        $dbdesc->{files}->{$file}->{index_extension} = read_zstring($fh);

        #
        # 5 16bit fields
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
        # Field description
        #
        for my $i ( 1 .. $dbdesc->{files}->{$file}->{number_of_fields} ) {

            # fieldname (zstring ?)
            my $fieldname = read_zstring($fh);

            $dbdesc->{files}->{$file}->{fields}->[$i] = $fieldname;

            # get type (if defined) from DDM
            if ( defined $dbdesc->{ddm_fields}->{$fieldname}->{type} ) {
                $fdt->{$fieldname}->{type} =
                  $dbdesc->{ddm_fields}->{$fieldname}->{type};
            }

            # Read field len (in bytes)
            $fdt->{$fieldname}->{len} = read_u16le($fh);    # field len

            # 4 unknown 16 bit integers (or 8 8bit, or combination, etc.)
            for ( 1 .. 4 ) {
                push @{ $fdt->{$fieldname}->{info} }, read_u16le($fh);
            }
        }

        #
        # Informations sur les champs ou index ??
        #
        for my $i ( 1 .. $dbdesc->{files}->{$file}->{number_of_fields} ) {
            my $fieldname = $dbdesc->{files}->{$file}->{fields}->[$i];

            #
            # 4 unknown 16 bit integers
            #
            for ( 1 .. 4 ) {
                push @{ $dbdesc->{files}->{$file}->{more_info} },
                  read_u16le($fh);
            }
        }

        $dbdesc->{files}->{$file}->{ 'unknown' . $unknown++ } = read_u16le($fh);

        # Field text description
        foreach my $i ( 1 .. $dbdesc->{files}->{$file}->{number_of_fields} ) {
            my $fieldname = $dbdesc->{files}->{$file}->{fields}->[$i];
            $fdt->{$fieldname}->{desc} = read_lstring($fh);
            chomp $fdt->{$fieldname}->{desc};
        }

        # assign our shortcut to dbdesc.
        $dbdesc->{files}->{$file}->{fields} = $fdt;

        #
        # Are we done on this file ?
        #
        my $cur = tell $fh;
        seek $fh, 0, SEEK_END;    # set at the end
        my $end = tell $fh;
        carp "Still " . $end - $cur . " bytes to read on $filename"
          if $end != $cur;

        if ( !close $fh ) {
            croak "Cannot close $filename : $ERRNO";
        }
    }

    return $dbdesc;
}

=head2 bin_dump

Dump the content of data files in a human readable format.

=cut

sub bin_dump {
    my ($dbdesc) = @_;

    my @files = keys %{ $dbdesc->{files} };

    #print Dumper $dbdesc;

    foreach my $file (@files) {
        my $pnt      = $dbdesc->{files}->{$file}->{pnt};
        my $filename = $dbdesc->{files}->{$file}->{data_file};
        my $fh;
        if ( !open $fh, '<', $filename ) {
            croak "Couldn't open file $filename: $ERRNO\n";
        }
        binmode $fh;

        # Get field pointer from dbdesc
        my $field = $dbdesc->{ddm_fields};

        # Get field list
        my @fields = map { $field->{$_}->{name} } grep { m{ \A \d+ \z}imxs }
          keys %{$field};
        print "Fields :", Dumper \@fields;
        foreach my $f (@fields) {
            print "$f : type=$field->{$f}->{type}\n";
        }
        my $nr = 0;
        while ( !eof($fh) ) {
            print STDERR "New record -------------\n";
            foreach my $f (@fields) {
                print STDERR "Reading type $field->{$f}->{type} : ";
                my $m   = $data_method{ $field->{$f}->{type} };
                my $buf = $m->($fh);

                #$buf = decode( 'iso-8859-1', $buf);
                $buf = decode( 'cp1252', $buf );

                # $field->{$f}->{len});

                print STDERR $buf . "\n";
            }
        }
        if ( !close $fh ) {
            croak "Cannot close $filename : $ERRNO";
        }
    }

    return $dbdesc;
}

1;

__END__

=head1 DIAGNOSTICS

=head1 CONFIGURATION AND ENVIRONMENT

=head1 DEPENDENCIES

adar relies on the following non core module : C<Data::HexDump>.

=head1 INCOMPATIBILITIES

Many ! This is in development.

=head1 BUGS AND LIMITATIONS

Many ! This is in development.

=head1 AUTHOR 

Your mileage may vary.

=head1 LICENSE AND COPYRIGHT

This code is public domain, I do not claim any rights on it.

=cut
