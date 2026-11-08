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
my $select = IO::Select->new($listener);
my (%buffer, %id, %remaining, %expected, $next);
print "Echo server on 127.0.0.1:54000 (CTRL-C to stop)\n";

while (1) {
    for my $sock ($select->can_read(1)) {
        if ($sock == $listener) {
            my $client = $listener->accept or next;
            $client->autoflush(1);
            my $fd = fileno($client);
            $id{$fd} = ++$next;
            $buffer{$fd} = '';
            $select->add($client);
            printf "[%.3f] connected #%d (%d active)\n",
                time(), $id{$fd}, $select->count - 1;
            print {$client} "split";
            print {$client} " line\nsecond line\n";
            next;
        }
        my $fd = fileno($sock);
        my $n = sysread($sock, my $data, 8192);
        if (!defined($n) || !$n) {
            $select->remove($sock);
            close($sock);
            printf "[%.3f] disconnected #%d (%d active)\n",
                time(), delete($id{$fd}), $select->count - 1;
            delete($buffer{$fd});
            delete($remaining{$fd});
            delete($expected{$fd});
            next;
        }
        $buffer{$fd} .= $data;
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
