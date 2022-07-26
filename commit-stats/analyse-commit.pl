#!/usr/bin/perl
use Date::Parse;

local $do_print = 2;

sub parse_hunk_header {
	my ($line) = @_;
	my ($o_ofs, $o_cnt, $n_ofs, $n_cnt) =
	    $line =~ /^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/;
	$o_cnt = 1 unless defined $o_cnt;
	$n_cnt = 1 unless defined $n_cnt;
	return ($o_ofs, $o_cnt, $n_ofs, $n_cnt);
}

sub get_blame_prefix {
	my ($line) = @_;
	$line =~ /^(\^?[0-9a-f]+\s+(\S+\s+)?\([^\)]+\))/ or die "bad blame output: $line";
	return $1;
}

sub git_rev_parse { 
	my ($rev_arg) = @_;
	my ($revparse);
	open($revparse, '-|', 'git', 'rev-parse', $rev_arg) or die;
	if (my $rev = <$revparse>) { chomp($rev); return $rev; } else { die };
}

sub is_api_change {
	my ($newrev) = @_;
	my ($oldrev) = "$newrev~1" ;
	print STDERR "DEBUG: check if $newrev is an API change\n" if $do_print > 1;
	open($diff, '-|', 'git', '--no-pager', 'diff', "-U5", $oldrev, $newrev) or die;
	my (@anchor_commits);

	my ($pre, $post);
	my $filename;
	my $final_result = 0;
	while (<$diff>) {
		if (m{^diff --git ./(.*) ./\1$}) {
			close $pre if defined $pre;
			close $post if defined $post;
			# print if ($do_print);
			$prefilename = "./" . $1;
			$postfilename = "./" . $1;
			$delete = $create = 0;
		} elsif (m{^diff --git ./(.*) ./(.*)$}) {
			close $pre if defined $pre;
			close $post if defined $post;
			# print if ($do_print);
			$prefilename = "./" . $1;
			$postfilename = "./" . $2;
			$delete = $create = 0;
		} elsif (m{^similarity index \d+\%$}) {

		} elsif (m{^new file}) {
			$create = 1;
			$prefilename = '/dev/null';
		} elsif (m{^deleted file}) {
			$delete = 1;
			$postfilename = '/dev/null';
		} elsif (m{^--- $prefilename$}) {
			# ignore
			# print if ($do_print);
		} elsif (m{^rename from $prefilename$}) {
			# ignore
			# print if ($do_print);
		} elsif (m{^\+\+\+ $postfilename$}) {
			# ignore
			# print if ($do_print);
		} elsif (m{^rename to $postfilename$}) {
			# ignore
			# print if ($do_print);
		} elsif (m{^@@ }) {
			my ($o_ofs, $o_cnt, $n_ofs, $n_cnt)
				= parse_hunk_header($_);
			my $o_end = $o_ofs + $o_cnt - 1;
			my $n_end = $n_ofs + $n_cnt - 1;
			if (!$create) {
				if ($prefilename =~ /\.api$/) {
					$final_result = 1;
				}
			}
			if (!$delete) {
				if ($postfilename =~ /\.api$/) {
					$final_result = 1;
				}
			}
		}
	}
	return($final_result);
}


sub get_anchor_commits {
	my ($newrev, $rev_filter_func) = @_;
	my ($oldrev) = "$newrev~1" ;
	print STDERR "DEBUG: Getting anchor commits for $newrev" if $do_print > 1;
	open($diff, '-|', 'git', '--no-pager', 'diff', "-U5", $oldrev, $newrev) or die;
	my (@anchor_commits);
	my (@touched_commits);
	my (@edited_commits);

	my ($pre, $post);
	my $filename;
	my $prev_anchor_commit = "invalid";
	my $curr_anchor_commit = "invalid";
	my $curr_edit_commit = "invalid";
	my $curr_edit_type = "none";
	while (<$diff>) {
		if (m{^diff --git ./(.*) ./\1$}) {
			close $pre if defined $pre;
			close $post if defined $post;
			# print if ($do_print);
			$prefilename = "./" . $1;
			$postfilename = "./" . $1;
			$delete = $create = 0;
		} elsif (m{^diff --git ./(.*) ./(.*)$}) {
			close $pre if defined $pre;
			close $post if defined $post;
			# print if ($do_print);
			$prefilename = "./" . $1;
			$postfilename = "./" . $2;
			$delete = $create = 0;
		} elsif (m{^similarity index \d+\%$}) {

		} elsif (m{^new file}) {
			$create = 1;
			$prefilename = '/dev/null';
		} elsif (m{^deleted file}) {
			$delete = 1;
			$postfilename = '/dev/null';
		} elsif (m{^--- $prefilename$}) {
			# ignore
			# print if ($do_print);
		} elsif (m{^rename from $prefilename$}) {
			# ignore
			# print if ($do_print);
		} elsif (m{^\+\+\+ $postfilename$}) {
			# ignore
			# print if ($do_print);
		} elsif (m{^rename to $postfilename$}) {
			# ignore
			# print if ($do_print);
		} elsif (m{^@@ }) {
			my ($o_ofs, $o_cnt, $n_ofs, $n_cnt)
				= parse_hunk_header($_);
			my $o_end = $o_ofs + $o_cnt - 1;
			my $n_end = $n_ofs + $n_cnt - 1;
			if (!$create) {
				open($pre, '-|', 'git', 'blame', '-l', '-M', "-L$o_ofs,$o_end",
				     $oldrev, '--', $prefilename) or die;
			}
			if (!$delete) {
				if ($newrev) {
					open($post, '-|', 'git', 'blame', '-l', '-M', "-L$n_ofs,$n_end",
					     $newrev, '--', $postfilename) or die;
				} else {
					open($post, '-|', 'git', 'blame', '-l', '-M', "-L$n_ofs,$n_end",
					     '--', $postfilename) or die;
				}
			}
		} elsif (m{^ }) {
			my $prefix = get_blame_prefix(scalar <$pre>);
	                $prefix =~ /^(\^?[0-9a-f]+)\s+((\S+\s+)?\([^\)]+\))/ or die "bad blame output: $prefix";
			my $commit = $1;
			print STDERR "    ", $prefix, "\t", $_ if $do_print > 1;
			push(@anchor_commits, $commit);
			if ($curr_anchor_commit ne $commit) {
				print STDERR "EEE => set anchor to $commit\n" if $do_print > 1;
				if ($curr_edit_type eq "add" && $prev_anchor_commit ne "invalid") {
					# addition happened without deletion - consider it an edit
					push(@edited_commits, $commit);
				        print STDERR "EEE => add edited commit  $commit\n" if $do_print > 1;
					push(@edited_commits, $prev_anchor_commit);
				        print STDERR "EEE => add prev edited commit  $prev_anchor_commit\n" if $do_print > 1;
				}
				$curr_anchor_commit = $commit;
				$curr_edit_commit = "invalid";
				$curr_edit_type = "none";
			}
			scalar <$post>; # discard
		} elsif (m{^\-}) {
			my $prefix = get_blame_prefix(scalar <$pre>);
			print STDERR " -  ", $prefix, "\t", $_,"" if $do_print > 1;
	                $prefix =~ /^(\^?[0-9a-f]+)\s+((\S+\s+)?\([^\)]+\))/ or die "bad blame output: $prefix";
			my $commit = $1;
			if ($curr_edit_commit ne $commit) {
				$curr_edit_commit = $commit;
				$curr_edit_type = "del";
				$prev_anchor_commit = $curr_anchor_commit;
				$curr_anchor_commit = "invalid";
			}
			push(@touched_commits, $commit);
			push(@edited_commits, $commit);
		} elsif (m{^\+}) {
			my $prefix = get_blame_prefix(scalar <$post>);
			print STDERR " +  ", $prefix, "\t", $_,"" if $do_print > 1;
	                $prefix =~ /^(\^?[0-9a-f]+)\s+((\S+\s+)?\([^\)]+\))/ or die "bad blame output: $prefix";
			my $commit = $1;
			if ($curr_edit_commit ne $commit) {
				$curr_edit_commit = $commit;
				$curr_edit_type = "add";
				$prev_anchor_commit = $curr_anchor_commit;
				$curr_anchor_commit = "invalid";
			}
			push(@touched_commits, $commit);
		}
	}
	my @sorted_anchor_commits = sort(@anchor_commits);
	my $last_commit = "";
	my @out_commits;
	foreach(sort(@edited_commits)) {
	  if ($last_commit ne $_) {
	    push(@out_commits, $_);
	    $last_commit = $_;
	  }
	}
        if (0) {
	foreach(sort(@touched_commits)) {
	  if ($last_commit ne $_) {
	    push(@out_commits, $_);
	    $last_commit = $_;
	  }
	}
	foreach(@sorted_anchor_commits) {
		if ($last_commit ne $_) {
			$last_commit = $_;
			if($rev_filter_func->($last_commit)) {
				push(@out_commits, $last_commit);
			}
		}
	}
	} # end if 0
	
	@out_commits;
}

sub is_interesting {
	my $commit_id = $_[0];
	print("Check if $commit_id is interesting..");
	$ancestor = `git rev-parse v20.05-rc0~1`;
	$full_commit_id = `git rev-parse $commit_id`;
	my $history = `git rev-list $full_commit_id`;
	if ($history =~ /$ancestor/) {
		print("YES\n");
		return(1);
	} else {
		print("NOT\n");
		return(0);
	}
}


# line-buffered
$|++;

sub get_commit_date {
	my $commit_id = $_[0];
	my $date_type = $_[1];
	my $out_date = 0;
	my $o = `git log --pretty=fuller $commit_id~1..$commit_id 2>&1`;
  
	my @lines = split("\n", $o);
	if ($date_type eq "") {
		die("need commit date type");
	}
  
	foreach (@lines) {
		chomp();
		# print(">>> $_\n");
		if (/^\s*${date_type}:\s*(.*)$/) {
			my $x = $1;
			# print("Found date: '$x'\n");
			$out_date = str2time($x);
		}
	}
	if ($out_date == 0) {
		die("Could not parse date for $commit_id");
	}
	return $out_date;
}

sub get_commit_date_author {
	return(get_commit_date($_[0], "AuthorDate"));
}
sub get_commit_date_commit{
	return(get_commit_date($_[0], "CommitDate"));
}

sub get_commit_type {
    my $commit_id = $_[0];
    my $commit_type = "unknown";
    my $o = `git log --pretty=fuller $commit_id~1..$commit_id 2>&1`;
    my @lines = split("\n", $o);
    foreach (@lines) {
	    chomp();
	    if (/^\s*Type:\s*(\S+)\s*$/i) {
		    $commit_type = lc($1);
	    }
    }
    if ($commit_type eq "unknown") {
	    print("ERROR: Could not determine commit type for $commit_id\n");
    }
    return $commit_type;
}

sub get_commit_release {
    my $commit_id = $_[0];
    if ($commit_id eq "invalid") {
	    die("invalid commit id");
    }
    my $o = `git describe $commit_id 2>&1`;
    chomp($o);
    $o =~ s/^(v..\...).*/\1/;
    return $o;
}



sub analyze_commit {
    my $commit_id = $_[0];
    my $commit_type = get_commit_type($commit_id);
    my $commit_release = get_commit_release($commit_id);

    if ($commit_type ne "fix") {
	    print("Commit type: $commit_type, skip\n");
	    return;
    }
    if ($commit_id eq "4ba3c0a8d82ff24492fbb858ab8fdef78bd3f4b9") {
	    print("special-case, skip\n");
    }

    my $commit_date = get_commit_date_commit($commit_id); # when was this fix discovered
    # interesting artifacts eg ac199fcd9ba16a9dc3657f8ee02c2a2c82a65417
    # my $commit_date = get_commit_date_author($commit_id); # when was this fix discovered

    my @anchor_commits = get_anchor_commits($commit_id, \&is_interesting);

    my $bug_date = 0;
    my $bug_id = "invalid";

    foreach (@anchor_commits) {
	    my $anchor_commit = $_;
	    # my $new_bug_date = get_commit_date_author($anchor_commit);
	    my $new_bug_date = get_commit_date_commit($anchor_commit);
	    if ($new_bug_date > $bug_date || $bug_date == $commit_date) {
		    # print("****** Use $anchor_commit as new bug date\n");
		    $bug_date = $new_bug_date;
		    $bug_id = $anchor_commit;
	    }

	    my $o = `git log $anchor_commit~1..$anchor_commit 2>&1`;
	    $o =~ s/^/=D= /gm;
	    $output = $output . "\n" . $o;
    }
    if ($bug_date == 0) {
	    print ("ERROR: Could not determine bug date for $commit_id\n");
	    return;
    }
    print ("Bug date: $bug_date bug id: $bug_id\n");
    my $bug_release = get_commit_release($bug_id);

    my $time_to_fix = ($commit_date - $bug_date) / (3600*24);



    print("$output\n");

    print("Time to fix for $commit_id: $time_to_fix days\n");
    print("Bug release: $bug_release Fix release: $commit_release\n");
    if ($bug_release eq $commit_release) {
	    if ($time_to_fix < 21) {
		    print("FIXED BEFORE RELEASE $bug_release but within 21 days\n");
	    } else {
		    print("FIXED BEFORE RELEASE $bug_release AND after 21 days\n");
	    }
    } else {
	    print("FIXED AFTER RELEASE $bug_release\n");
    }
    
    print("TTF: $time_to_fix\n");

}

sub get_commits {
    my $since = $_[0] || "HEAD~100";
    my $o = `git log --reverse --pretty=oneline $since.. 2>&1`;
    my @lines = split("\n", $o);
    foreach (@lines) {
	    chomp();
	    if (/^([0-9a-f]+)\s*/) {
		    my $commit_id = $1;
		    print("ANALYZING $commit_id\n");
		    analyze_commit($commit_id);
	    } else {
		    die("Can not parse $_");
	    }
    }
}

# analyze_commit("4ba3c0a8d82ff24492fbb858ab8fdef78bd3f4b9");
# exit(1);
get_commits($ARGV[0]);

# analyze_commit("ac199fcd9ba16a9dc3657f8ee02c2a2c82a65417");
# analyze_commit("59a08e65094db28884fc40e9562e303fde3b21d8");
# analyze_commit("f8631ce7e8886136b4543a7926ffdf1bc760fb11");
# analyze_commit("2d7665758e7c234d7247a3793c1e741c61f4382e");
