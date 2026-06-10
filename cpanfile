requires 'perl', '5.008';

requires 'Carp';
requires 'Readonly';
requires 'Return::Set';
requires 'Scalar::Util';

on 'test' => sub {
	requires 'Test::Most';
	requires 'Test::DescribeMe';
	requires 'Test::Needs';
	requires 'Test::NoWarnings';
};

on 'develop' => sub {
	requires 'Devel::Cover';
	requires 'Perl::Critic';
	requires 'Test::Pod';
	requires 'Test::Pod::Coverage';
};
