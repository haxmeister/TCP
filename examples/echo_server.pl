#!/usr/bin/env perl
use strict;
use warnings;
use IO::Socket::INET;
use IO::Select;
use Time::HiRes qw(time);
$| = 1;

my $listener = IO::Socket::INET->new(
    LocalAddr => '127.0.0.1',
    LocalPort => 54000,
    Listen => 10,
    ReuseAddr => 1,
    Proto => 'tcp',
) or die "listen: $!\n";
my $delimiter_listener = IO::Socket::INET->new(
    LocalAddr => '127.0.0.1',
    LocalPort => 54001,
    Listen => 10,
    ReuseAddr => 1,
    Proto => 'tcp',
) or die "delimiter listen: $!\n";
my $select = IO::Select->new($listener, $delimiter_listener);
my (%buffer, %id, %remaining, %expected, %delimiter_client, $next);
print "Echo server on 127.0.0.1:54000 (delimiter test on :54001; CTRL-C to stop)\n";

while (1) {
    for my $sock ($select->can_read(1)) {
        if ($sock == $listener || $sock == $delimiter_listener) {
            my $special = $sock == $delimiter_listener;
            my $client = $sock->accept or next;
            $client->autoflush(1);
            my $fd = fileno($client);
            $id{$fd} = ++$next;
            $buffer{$fd} = '';
            $delimiter_client{$fd} = $special;
            $select->add($client);
            printf "[%.3f] connected #%d (%d active)%s\n",
                time(), $id{$fd}, $select->count - 2,
                $special ? ' [delimiter]' : '';
            if ($special) {
                print {$client} "first||second||";
            } else {
                print {$client} "split";
                print {$client} " line\nsecond line\n";
            }
            next;
        }
        my $fd = fileno($sock);
        my $n = sysread($sock, my $data, 8192);
        if (!defined($n) || !$n) {
            $select->remove($sock);
            close($sock);
            printf "[%.3f] disconnected #%d (%d active)\n",
                time(), delete($id{$fd}), $select->count - 2;
            delete($delimiter_client{$fd});
            delete($buffer{$fd});
            delete($remaining{$fd});
            delete($expected{$fd});
            next;
        }
        $buffer{$fd} .= $data;
        if ($delimiter_client{$fd}) {
            while ((my $pos = index($buffer{$fd}, "||")) >= 0) {
                my $message = substr($buffer{$fd}, 0, $pos + 2, '');
                $message =~ s/\|\|\z//;
                print "client #$id{$fd} delimiter: $message\n";
                print {$sock} "echo: $message||";
            }
            next;
        }
        while (length $buffer{$fd}) {
            if ($remaining{$fd}) {
                my $take = length($buffer{$fd}) < $remaining{$fd}
                    ? length($buffer{$fd}) : $remaining{$fd};
                substr($buffer{$fd}, 0, $take, '');
                $remaining{$fd} -= $take;
                if (!$remaining{$fd}) {
                    printf "client #%d: stress complete (%d bytes)\n", $id{$fd}, $expected{$fd};
                    print {$sock} "stress ok $expected{$fd}\n";
                    delete $remaining{$fd};
                    delete $expected{$fd};
                }
                next;
            }
            my $pos = index($buffer{$fd}, "\n");
            last if $pos < 0;
            my $line = substr($buffer{$fd}, 0, $pos + 1, '');
            $line =~ s/\r?\n\z//;
            if ($line =~ /^STRESS ([0-9]+)$/ && $1 > 0 && $1 <= 4_194_304) {
                $remaining{$fd} = $1;
                $expected{$fd} = $1;
                print "client #$id{$fd}: expecting $1 stress bytes\n";
            } else {
                print "client #$id{$fd}: $line\n";
                print {$sock} "echo: $line\n";
            }
        }
    }
}
