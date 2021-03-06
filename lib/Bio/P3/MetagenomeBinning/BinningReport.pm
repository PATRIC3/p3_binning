package Bio::P3::MetagenomeBinning::BinningReport;

use strict;
use Data::Dumper;
use URI::Escape;
use File::Basename;
use Template;
use Module::Metadata;
use Bio::KBase::AppService::AppConfig 'seedtk';
use File::Slurp;

#
# Write the binning summary report.
#
# Uses the quality and PPR reports generated by the
# pipeline epilog script.

sub write_report
{
    my($job_id, $params, $quality_report, $ppr_report, $bins, $group_path, $output_fh) = @_;

    #
    # Read the seedtk role map in case we need it.
    #
    my %role_map;
    if (open(R, "<", seedtk . "/data/roles.in.subsystems"))
    {
	while (<R>)
	{
	    chomp;
	    my($abbr, $hash, $role) = split(/\t/);
	    $role_map{$abbr} = $role;
	}
	close(R);
    }

    my $templ = Template->new(ABSOLUTE => 1);

    #
    # Extract genomes from qual report and mark up. Create good and bad genome lists.
    #

    my $min_scikit = 85;
    my $min_checkm = 80;

    my $good = [];
    my $bad = [];

    my $url_base = 'https://www.patricbrc.org/view/Genome';
    my $fid_url_base = 'https://www.patricbrc.org/view/Genome';

    my $all_pkgs = $quality_report->{packages};
    
    @$all_pkgs = sort { ($b->{checkm_completeness} + $b->{scikit_fine}) <=>
			    ($a->{checkm_completeness} + $a->{scikit_fine}) } @$all_pkgs;

    for my $gpkg (@$all_pkgs)
    {
	my $url = "$url_base/$gpkg->{genome_id}";
	$gpkg->{genome_url} = $url;
	if ($gpkg->{checkm_completeness} >= $min_checkm &&
	    $gpkg->{scikit_fine} >= $min_scikit)
	{
	    push(@$good, $gpkg);
	}
	else
	{
	    push(@$bad, $gpkg);
	}

	#
	# Scan the bins to find the reference genome.
	#
	my($bin) = grep { $_->{name} eq $gpkg->{genome_name} } @$bins;
	$gpkg->{reference_genomes} = [];
	if ($bin)
	{
	    push(@{$gpkg->{reference_genomes}}, @{$bin->{refGenomes}});
	}
	$gpkg->{reference_urls} = [ map { { reference_genome => $_, reference_url => "$url_base/" . uri_escape($_) } } @{$gpkg->{reference_genomes}} ];
    }

    #
    # Process the ppr report to have a toplevel list of ppr info per genome.
    #
    my $ppr = [];

    for my $gpkg (@$all_pkgs)
    {
	my $p = $ppr_report->{$gpkg->{genome_id}};
	my $r1 = $p->{role_ppr};

	my @roles;
	while (my($abbr, $vec) = each %$r1)
	{
	    my $role = $p->{roles}->{$abbr} // $role_map{$abbr};
	    my($predicted, $actual) = @$vec;
	    my $fids = $p->{role_fids}->{$abbr};
	    $fids //= [];
	    my $url;
	    if (@$fids == 1)
	    {
		$url = "https://www.patricbrc.org/view/Feature/" . uri_escape($fids->[0]);
	    }
	    elsif (@$fids > 1)
	    {
		my $list = join(",", map { uri_escape(qq("$_")) } @$fids);
		$url = "https://www.patricbrc.org/view/FeatureList/?in(patric_id,($list))";
	    }

	    push(@roles, { role => $role, abbr => $abbr, predicted => $predicted, actual => $actual,
			   fids => $fids, fid_url => $url, n_fids => scalar @$fids });
	}
	@roles = sort { $a->{role} cmp $b->{role} } @roles;
	my $ppr_count = scalar keys %$r1;
	my $pent = {
	    genome_id => $gpkg->{genome_id},
	    ppr_count => $ppr_count,
	    roles => \@roles,
	};
	$gpkg->{ppr} = $pent;
	push(@$ppr, $pent);
    }
    
    my $vars = {
	min_checkm => $min_checkm,
	min_scikit => $min_scikit,
	job_id => $job_id,
	params => $params,
	qual => $quality_report,
	ppr_report => $ppr_report,
	ppr => $ppr,
	good => $good,
	bad => $bad,
	genome_group_path => $group_path,
    };
    # write_file("debug", Dumper($vars));
    my $mod_path = Module::Metadata->find_module_by_name(__PACKAGE__);
    my $tt_file = dirname($mod_path) . "/BinningReport.tt";
    $templ->process($tt_file, $vars, $output_fh) || die "Error processing template: " . $templ->error();
    
}

1;


