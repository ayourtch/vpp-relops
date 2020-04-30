#
# Generate the release notes automatically in the style of 20.01 release notes



use Data::Dumper;


# make string ready to be used for RELEASE.md
sub mdstring {
	my $string = $_[0];
	# those that do not happen in the CLIs
	my $acronyms = [ 'vpp', 'sack', 'rtt', 'dpdk' ];
	foreach $my_acro (@{$acronyms}) {
		$string =~ s/\b$my_acro\b/uc($my_acro)/gex;
	}

	$string =~ s/^(\w)/\U$1/;
	# escape the '_' for markdown
	$string =~ s/([<>_])/\\$1/g;
	return $string;
}

# the command string passed as argument here should be something like:
# "git log --oneline --reverse --decorate=no --grep 'Type: component' v19.08.1..stable/1908"
#
sub collect_commits {
	my $cmd = $_[0];
	my $command_output = `$cmd`;
	my $out = {};
	foreach $aLine (split(/[\r\n]+/, $command_output)) {
		if ($aLine =~ /^([0-9a-fA-F]+) ([^:]+): (.+)$/) {
			my $aCommitID = $1;
			my @aComponents = split(' ', $2);
			my $aComponent = $aComponents[0];
			my $aComment = $3;
			if (!exists($out->{$aComponent})) {
				$out->{$aComponent} = [];
			}
			my $aEntry = { 'commit_id' => $aCommitID, 'comment' => $aComment, 'comment_r' => mdstring($aComment) };
			push(@{$out->{$aComponent}}, $aEntry);
		}
	}
	return $out;
}



# 
# Read the maintainers file into a hash, indexed by short component name,
# for now just reads short name and long name.
#
sub read_maintainers() {
	open(F, "MAINTAINERS") || die("Could not open MAINTAINERS file");
	my $short_name = "";
	my $long_name = "";
	my $in_component = 0;
	my $out = {};
	while (<F>) {
		chomp();
		my $aLine = $_;
		# print ("LINE: $aLine\n");
		if (/^([A-Z]):\s+(.*)$/) {
			my $aLetter = $1;
			my $aValue = $2;
			# print ("LETTER: $aLetter, VALUE: $aValue\n");
			if ($aLetter eq "I") {
				$short_name = $aValue;
			}
			# FIXME: deal with all the other letters here
		} elsif (/^(\s*)$/) {
			if ($in_component) {
				$in_component = 0;
				if ($short_name ne "") {
					my $comp = {};
					$comp->{'short_name'} = $short_name;
					$comp->{'name'} = $long_name;
					$out->{$short_name} = $comp;
					# print("FEATURE: $short_name => $long_name\n");
					$short_name = "";
					$long_name = "";
				}
			}
			# print ("END\n");
		} elsif (/^([^\s].*)$/) {
			$in_component = 1;
			$long_name = $1;
		}
	}
	return($out);
}


# print the markdown version of the release notes generated based on the components hash
# and the commits-per-component hash
sub print_markdown {
	my $components = $_[0];
	my $commits = $_[1];
	my $base_indent = $_[2];

	# section prefixes to group the components into
	my $section_prefixes = { "VNET " => "VNET", "Plugin - " => "Plugins" };

	# Sort the component list by alphabetical order of the human-friendly component name
	my @componentlist = sort({$components->{$a}->{'name'} cmp $components->{$b}->{'name'}} keys(%{$components}));

	my @result = map { "$_: $components->{$_}->{'name'}" } @componentlist;
	# print Dumper(\@componentlist);

	# print Dumper(\@result);
	# print Dumper($commits);

	my $indent = $base_indent;
	my $in_section = 0;
	my $section_prefix = "";

	foreach $aFeature (@componentlist) {
		my $component_name = $components->{$aFeature}->{'name'};
		if ($in_section) {
			if (rindex($component_name, $section_prefix, 0) != 0) {
				$in_section = 0;
				$section_prefix = "";
				$indent = $base_indent;
			}

		}
		if (length($commits->{$aFeature}) == 0) {
			next;
		}
		# the "in_section" might have been just reset, so need another branch
		if (!$in_section)	{
			foreach $aPrefix (keys %{$section_prefixes}) {
				if (rindex($component_name, $aPrefix, 0) == 0) {
					$in_section = 1;
					$section_prefix = $aPrefix;
					my $section_name = $section_prefixes->{$aPrefix};
					print("$indent- $section_name\n");
					$indent = "$base_indent  ";
					break;
				}
			}
		}
		if ($in_section) {
			$component_name =~ s/^$section_prefix//g;
		}
		$component_name = mdstring($component_name);
		print("$indent- $component_name\n");
		foreach $aCommit (@{$commits->{$aFeature}}) {
			# print(Dumper($aCommit));
			my $msg = $aCommit->{'comment_r'};
			my $cid = $aCommit->{'commit_id'};
			my $aOutLine = "$msg ($cid)";
			print("$indent  - $aOutLine\n");
		}
	}
}

sub print_components_header {
	my $a = <<__E__;
@page release_notes_2001 Release notes for VPP 20.01

More than 1039 commits since the 19.08 release.

## Features

__E__

}

my $components = read_maintainers();
my $commits = collect_commits("git log --oneline --reverse --decorate=no --grep 'Type: feature' v19.08.1..stable/1908");
# my $commits = collect_commits("git log --oneline --reverse --decorate=no --grep 'VPP-' v19.08.1..stable/1908");

# print Dumper($commits);
print_markdown($components, $commits);


