#!/usr/bin/perl

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

	my ($pre, $post);
	my $filename;
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
			scalar <$post>; # discard
		} elsif (m{^\-}) {
			my $prefix = get_blame_prefix(scalar <$pre>);
			print STDERR " -  ", $prefix, "\t", $_,"" if $do_print > 1;
	                $prefix =~ /^(\^?[0-9a-f]+)\s+((\S+\s+)?\([^\)]+\))/ or die "bad blame output: $prefix";
			my $commit = $1;
			push(@touched_commits, $commit);
		} elsif (m{^\+}) {
			my $prefix = get_blame_prefix(scalar <$post>);
			print STDERR " +  ", $prefix, "\t", $_,"" if $do_print > 1;
	                $prefix =~ /^(\^?[0-9a-f]+)\s+((\S+\s+)?\([^\)]+\))/ or die "bad blame output: $prefix";
			my $commit = $1;
			push(@touched_commits, $commit);
		}
	}
	my @sorted_anchor_commits = sort(@anchor_commits);
	my $last_commit = "";
	my @out_commits;
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

sub cherry_pick_commit {
  my $fix_id = $_[0];
    $fix_id = $1;
    if (is_api_change($fix_id)) {
      print("API-: $str\n");
      next;
    }
    if ($skipping && ($fix_id eq $skip_until)) {
    	print("Found $skip_until !");
    	$skipping = 0;
    }
    if ($skipping) {
	print("skipping $fix_id!");
        next;
    }

    $output = `git cherry-pick -x $fix_id 2>&1`;
    $ret_code = $?;
    local $status = "OK++";
    if ($ret_code != 0) {
      system("git reset --hard HEAD >/dev/null 2>/dev/null");
      if ($output =~ /The previous cherry-pick is now empty/) {
	$status="OK--";
      } else {
        $status = "ERR-";
	my @anchor_commits = get_anchor_commits($fix_id, \&is_interesting);
	foreach (@anchor_commits) {
		my $anchor_commit = $_;
    		my $o = `git log $anchor_commit~1..$anchor_commit 2>&1`;
		$o =~ s/^/=D= /gm;
		$output = $output . "\n" . $o;

	}
      }
    }
    if ($status eq "OK++") {
	    # system("git diff -U0 --no-color HEAD~1..HEAD | python3 ~/clang/tools/clang-format/clang-format-diff.py -p1 -i");
	    # system("git commit -a --amend --no-edit");
      $check_ext_deps = `make -C build/external check-deb`;
      my $ext_deps_rebuilt = 0;
      if ($check_ext_deps =~ /Out of date/) {
	      print("Need to rebuild ext-deps..");
	      $output = $output . $check_ext_deps;
              my $deps_build_output = `make install-ext-deps`;
	      $output = $output . $deps_build_output;
              my $ret_code = $?;
              if ($ret_code != 0) {
		system("git reset --hard HEAD~1 >/dev/null 2>/dev/null");
	        $status = "ERR+";
                my $deps_build_output = `make install-ext-deps`;
                my $ret_code = $?;
		if ($ret_code != 0) {
			print("pending output: " . $output);
			print("output when trying to build the old ext deps: " . $deps_build_output);
			die("Could not rollback the ext-deps to older version");
		}
	      }
	      $ext_deps_rebuilt = 1;
	      
      }
    }
    if ($status eq "OK++") {
      $build_output = `make build`;
      $ret_code = $?;
      if ($ret_code != 0) {
	      print("BUILD-ERR:" . $build_output);
	      system("git clean -fdx");
              $build_output = `make build`;
              $ret_code = $?;
      }
      if ($ret_code != 0) {
	system("git reset --hard HEAD~1 >/dev/null 2>/dev/null");
	$status = "ERR+";
	$build_output =~ s/^/=B=/gm;
	$output = $output . $build_output;
	print($output);
	print("Could not compile!");
      }
    }

    my $time_end = localtime();
    my $elapsed = $time_end - $time_start;
    print("ELAPSED: $elapsed sec\n");

    print("$status: $str\n");
    if (status =~ /^ERR/) {
	    # die ("Could not apply a diff");
    }
    print("$output\n");

}

sub check_git_config {
	my $user_name = `git config  --get user.name`;
	if ($user_name eq "") {
		system("git config user.name 'Andrew Yourtchenko'");
		system("git config user.email 'ayourtch\@gmail.com'");
	}
}

check_git_config();
print("Cherry-pick commit: $ARGV[0]");
exit(0);
cherry_pick_commit($ARGV[0]);
