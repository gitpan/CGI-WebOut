#
# �����������, ��� ����� ����� print ����� ��������� ��������� � �������.
# �� ����, ���������� ���, ������ �� �����������, � ����� �� ���, �����
# ��������� Content-type ������ ��������� ����� ������� ���������.
# ������ ����� �����, ������ �� ��������, ������������ � �������, � 
# �������������� �� � ������� (� ���� ������������ ��� �������� ������).
# ����� ��������� ��������� ������������� �������� ����� ������� ���
# ����������� ���������: $text = grab { print "Hello" }.
# � �����, ������ �������� ��������� PHP.
#
# 23.08.2003
#   Now CGI::WebOut is fully tie-safe: if somebody ties STDOUT before
#   including module, all works correctly and transparently.
#
package CGI::WebOut;
our $VERSION = "2.02";

use strict;
use Exporter; our @ISA=qw(Exporter);
our @EXPORT=qw(
	ER_NoErr
	ER_Err2Browser 
	ER_Err2Comment 
	ER_Err2Plain
	ErrorReporting
	grab
	echo  
	SetAutoflush 
	NoAutoflush 
	UseAutoflush 
	Header
	HeadersSent
	Redirect
	ExternRedirect
	NoCache
	Flush
	try catch warnings throw
);


##
## ���������
##
sub ER_NoErr { 0 }                # ��������� ����� �� �������
sub ER_Err2Browser { 1 }          # ������ � �������������� ��������� � �������
sub ER_Err2Comment { 2 }          # �� ��, �� � ���� <!--...-->-������������
sub ER_Err2Plain { 3 }            # �� ��, �� � ���� plain-������


##
## ���������� ����������
##
our $DEBUG = undef;              # ���������� ����� - ������ ��� �����.
our $UseAutoflush = 1;           # ����� ���������� �������
our $HeadersSent = 0;            # �������: ��������� ��� �������
our @Headers = ();               # ��������� ������
our $NoCached = 0;               # �������� �� ����������
our $Redirected = 0;             # ���� �������������
our $ErrorReporting = 1;         # ����� ������ � ������� �������
our @Errors = ();                # ����� ������������� ������
our @Warns = ();                 # ��������������

# � ���������, ������ ����, ����� ������� ������� � �������� ������� ������, 
# ���������� ������� ���� ��������� ������. ���� � ���, ��� �������� �������
# ����������� ��� ������� ������, � ������, ���� � ��������� ����������:
#   $b = new CGI::WebOut();
#   ...
#   $b = undef;
# �� ���������� ��� $b ������ �� ����� (�.�. ������ �� ���� �������� � $CurObj).
# ���� �� ������� � �������� ������ �� ��������� ������, � ������ �� ����
# ������� ������������� �� �������, ���������� ����������, ��� ����.
#
# ��� ��� ����� ��������, ��� �������� � ���� ������ ������ �� ������� 
# ������ ������ ������ �����. ����� ���� �������� ������ �� ��� �����.
# ����� �������, echo ������ �������� �� ��������� �������, �� �� ��������.
our $rRootBuf = \(my $s="");     # ������� ����� ������
our $rCurBuf;                    # ������� ����� ������

#
# Algorythm is:
# 1. Tie STDOUT to newly created CGI::WebOut::Tie.
# 2. Constructor CGI::WebOut::Tie->RIEHANDLE creates new objecc CGI::WebOut
#    and stores its reference in its property. It is IMPORTANT that there 
#    are NO other reserences to this object stored in some other place.
# 3. That's why, when STDOUT is untied (in END or during global destruction)
#    CGI::WebOut object is destroyed too.
# 4. In destructor CGI::WebOut->DESTROY works code: if this object is the 
#    first (root), Flush() is called and errors are printed.
#


# Synopsis: use CGI::WebOut($restart=0)
# ��� ����������� ��������� ���������� STDOUT �, ���� ����������� ��� ���
# ��� ����������, ������������� �� �� ����.
#
# �������� ������������� FastCGI: import �������� �� ���, ��� �������� ��. 
# ��������, ���� � ����� � ����� ���������� �������� use CGI::WebOut, �� 
# ������� import ����� ������ ������ 1 ���. ���� ���� ������ �������� ��� �� 
# �������, �� import ��������� ������. �������������� import ����������� 
# ��������� ������������: eval("use CGI::WebOut(1)"). �� ������������� 
# ��������� ������ ����� ��������� ����������� FastCGI.
#
# ���� �������� $restart ����� true, �� ��� ���������� ���, ����� �� 
# ��������� ������ ��� ������� �� ����������.


##
## ������������� ����������� �������. 
##

# void retieSTDOUT($restart=false)
# ���������� ������ STDOUT (������� �������� - ����������, ����� �� 
# ��������������!) � ������������� ���� ����������� �� STDOUT. � ������, 
# ���� ���� ����������� ��� ����������, ������ �� ������. 
my $numReties;
sub retieSTDOUT
{	my ($needRestart) = @_;
	$needRestart ||= !$numReties++;
	# Handle all warnings and errors.
	$SIG{__WARN__} = sub { &Warning(($_[0] !~ /^\w+:/ ? "Warning: " : "").shift) };
	$SIG{__DIE__} = sub { return if ref $_[0]; &Warning(($_[0] !~ /^\w+:/ ? "Fatal: " : "").shift) };
	# ���� ����� ����� ������, ���������� ������� ������� ����������.
	if ($needRestart) {
		$HeadersSent = $Redirected = $NoCached = 0;
		@Headers = ();
		$$rRootBuf = '';
	}
	# ���� ������ �� ����������, �������
	return if tied(*STDOUT) && ref tied(*STDOUT) eq __PACKAGE__."::Tie";
	tie(*STDOUT, __PACKAGE__."::Tie", \*STDOUT, tied(*STDOUT));
}


# ���������, ������������ �� ���������� Web-�������� ��� �������
sub IsWebMode() { 
	return $ENV{SCRIPT_NAME}? 1 : 0 
}


# ������� �� ���������?
sub HeadersSent { 
	return $HeadersSent;
}


# static int echo(...)
# ������� ������ ���������� � ������� �������� �����. ���� ���� 
# ����� ��������� ��������������� � �������, �������� Flush().
# ���������� ����� ���������� ��������.
sub echo {
	# � ������ ������� undef-�������� � ������ ������ �� ��,
	# ��� � print.
	if(grep {!defined $_} @_) {
		# ���� ������ ��� - �� �������, ������ ������ �� ����������.
		eval { require Carp } 
			and Carp::carp("Use of uninitialized value in print"); 
	}
	my $txt = join("", map { defined $_? $_:"" } @_); 
	return if $txt eq "";
	$$rCurBuf .= $txt;
	Flush() if $UseAutoflush && $rCurBuf == $rRootBuf;
	return length($txt);
}


# �������� ��������� ������. �������������:
# $grabbed = grab { 
#     print 'Hello!' 
# } catch {
#     die "An error occurred while grabbing the output: $@";
# };
# ��� �� ��, �� ��� catch: 
# $grabbed = grab { print 'Hello!' };
sub grab(&@)
{	my ($func, $catch)=@_;
	my $Buf = CGI::WebOut->new; 
	$@ = undef; eval { &$func() };
	if ($@ && $catch) { chomp($@); local $_ = $@; &$catch; }
	return $Buf->buf;
}


# static Header($header)
# ������������� ��������� ������.
sub Header($)
{	my ($head)=@_;
	if ($HeadersSent) {
		eval { require Carp } 
			and Carp::carp("Oops... Header('$head') called after content had been sent to browser!\n"); 
		return undef; 
	}
	push(@Headers, $head);
	return 1;
}


# ���������� ���������� �������� ������ � �������.
sub Flush() {	
	# ��������� ���������� ����������� Perl-�
	local $| = 1;	
	# ���� ��������� ��� �� ��������, �������� ��
	if (!$HeadersSent && IsWebMode()) {
		my $ContType="text/html";
		unshift(@Headers,"X-Powered-By: CGI::WebOut v$VERSION (http://www.dklab.ru/chicken/4.html) by Dmitry Koteroff, (C) 2000-2003.");
		# ���� Content-type, ����� ����� ��������� ��� � �����
		for (my $i=0; $i<@Headers; $i++) {
			if ($Headers[$i]=~/^content-type: *(.*)$/i) {
				$ContType = $1; splice(@Headers, $i, 1); $i--;
				next;
			}
			if ($Headers[$i]=~m/^location: /i) {
				$Redirected = 1;
			}
		}
		push(@Headers, "Content-type: $ContType");
		my $headers = join("\n",@Headers)."\n\n";
		if (!$Redirected) {
			# Prepend the output buffer with headers data.
			# So we output the buffer and headers in ONE print call (it is 
			# more transparent for calling code if it ties STDOUT by himself).
			$$rRootBuf = $headers.$$rRootBuf;
		} else {
			# Only headers should be sent. 
			_RealPrint($headers);
		}
		$HeadersSent = 1;
	}
	# ��������� ����� � �������� ���
	_Debug("Flush: len=%d", length($$rRootBuf));
	if (!$Redirected) { 
		_RealPrint($$rRootBuf);
	}
	$$rRootBuf = "";
	return 1;
}


# constructor new($refToNewBuf=undef)
# ������ ������� ����� ����� ������.
sub new
{	my ($class, $rBuf)=@_;
	$rBuf = \(my $b="") if !defined $rBuf;
	my $this = bless {
		rPrevBuf => $rCurBuf,
		rCurBuf  => $rBuf,
	}, $class;
	$rCurBuf = $rBuf;
	_Debug("[%s] New: prevSt=%s, curSt=%s", $this, $this->{rPrevBuf}, $this->{rCurBuf});
	return $this;
}


# ��������������� ���������� �������� ������ ������
sub DESTROY
{	my ($this)=@_;
	_Debug("[%s] DESTROY: prevSt=%s, curSt=%s", $this, $this->{rPrevBuf}, $this->{rCurBuf});

	# ���� ��� ��������� ������, �� ��������� ��������, ������� ����� �����������
	# ��������� � ������� ���������� ���������. �� ����, ���� ������� ���� �����������
	# ����� � ������ �����, ����� ���������� DESTROY ��� �������, ���������� �
	# STDOUT, �� ���� ����� ����� ����������� ��������� (�� ������ ��� ��� - �� �����).
	# ��� ��� ��������� ����� ������ ������, ���, �����������, � Perl ������
	# �������� �������, ������� ����� ������������� ���������� � �����, �������� ���
	# ��������� ������... ������ ����� ������� ��������� ������, ������� ��� ����������� 
	# ������� ���� ����������. ����� �������� ��� ��� ����� ������, ���������
	# � STDOUT. ��� ��� �������� ����������, ������ ��� ����� ����� ����� ������� 
	# ��������� �, ��������, ��������� � ��������� �������. ���, ����������, � 
	# �������� �����.
	if ($rCurBuf == $rRootBuf) {
		# ���������� ������ ������� �� ����� ������������ print � STDOUT, ������ ���
		# � ������ ����������� ���� ����� STDOUT �� � ���� �� "��������", ��
		# Perl-� �������, ��� ��������, ������� ������������ GP Fault.
		&__PrintAllErrors() if @Errors;
		Flush();
		return;
	}
	$rCurBuf = $this->{rPrevBuf};
}


# string method buf()
# ���������� ��� ��������� ������ �� ������ ������.
sub buf { 
	return ${$_[0]->{rCurBuf}};
}



##
## ��������� ������� � ������.
##

# constructor _newRoot()
# Creates the new ROOT (!!!) buffer. Called internally while tying STDOUT.
sub _newRoot {
	$$rRootBuf = "";
	$rCurBuf = undef;
	goto &new;
}


# Package import.
sub import {
	my ($pkg, $needRestart)=@_;
	retieSTDOUT($needRestart);
	goto &Exporter::import;
}


# ���������� ������. ������ �� ���, ����� ��� ������� ���� ������� � 
# ���������� �������. ���������� �� ���� "global destruction", ��� 
# ��� � �����. ������, ���� ��������, ��� ������ END �� ����������
# (� ������ �����-�� ������), ������ � � ���� ������ ��� ����� ��������
# ��������� (��. _RealPrint).
sub END {
	return if !tied(*STDOUT) || ref tied(*STDOUT) ne __PACKAGE__."::Tie";
	CGI::WebOut::_Debug("END");
	untie(*STDOUT);
}


# static _RealPrint()
# Prints the data to "native" STDOUT handler.
sub _RealPrint {	
	my $obj = tied(*STDOUT);
	_Debug("_RealPrint: STDOUT tied: %s", $obj);
	my $txt = join("", @_);
	return if $txt eq "";
	if ($obj) { 
		return $obj->parentPrint(@_) 
	} else {
		# Sometimes, during global destruction, STDOUT is already untied
		# but print still does not work. I don't know, why. This workaround
		# works always.
		open(local *H, ">&STDOUT");
		return print H @_;
	}
}


# ��� ������� - ������� ��������� � ����
my $opened;
sub _Debug {	
	return if !$DEBUG;
	my ($msg, @args) = @_;

	# Detect "global destruction" stage.
	my $gd = '';
	{
		local $SIG{__WARN__} = sub { $gd .= $_[0] };
		warn("test");
		$gd =~ s/^.*? at \s+ .*? \s+ line \s+ \d+ \s+//sx;
		$gd =~ s/^\s+|[\s.]+$//sg;
		$gd = undef if $gd !~ /global\s*destruction/i;
	}
	local $^W;
	open(local *F, ($opened++? ">>" : ">").$DEBUG); 
	print F sprintf($msg, map { defined $_? $_ : "undef" } @args) . ($gd? "($gd)" : "")."\n";
}


##
## ��� ��������� ������ print-�
##

{{{
##
## This class is used to tie some Perl variable to specified $object
## WITHOUT calling TIE* method of ref($object). Unfortunately Perl
## does not support 
##   tied(thing) = something;
## construction. Instead of this use:
##   tie(thing, "CGI::WebOut::TieMediator", something).
## See tieobj() below.
##
package CGI::WebOut::TieMediator;
#sub TIESCALAR { return $_[1] }
#sub TIEARRAY  { return $_[1] }
#sub TIEHASH   { return $_[1] }
sub TIEHANDLE { return $_[1] }
}}}


{{{
##
## This class is used to tie objects to filehandle.
## Synopsis:
##   tie(*STDOUT, "CGI::WebOut::Tie", \*STDOUT, tied(*STDOUT));
## All the parent methods is virtually inherited. So you
## may call print(*FH, ...), close(*FH, ...) etc.
## All the output is redirected to current CGI::WebOut object.
## This class is used internally by the main module.
##
package CGI::WebOut::Tie;

# The same as tie(), but ties existed object to the handle.
sub tieobj { 
	return tie($_[0], "CGI::WebOut::TieMediator", $_[1]) 
}

## Fully overriden methods.
sub WRITE  { shift; return CGI::WebOut::echo(@_); }
sub PRINT  { shift; return CGI::WebOut::echo(@_); }
sub PRINTF { shift; return CGI::WebOut::echo(sprintf(@_)); }

# Creates the new tie. Saves the old object and handle reference.
# See synopsis above.
sub TIEHANDLE 
{	my ($cls, $handle, $prevObj) = @_;
	CGI::WebOut::_Debug("TIEHANDLE(%s, %s, %s)", $cls, $handle, $prevObj);
	return bless { 
		handle  => $handle,
		prevObj => $prevObj,
		outObj  => CGI::WebOut->_newRoot($rRootBuf),
	}, $cls;
}

sub DESTROY {
	CGI::WebOut::_Debug("[%s] DESTROY", $_[0]);
}

## Methods, inherited from parent.
sub CLOSE 
{	my ($this) = @_;
	CGI::WebOut::Flush();
	$this->parentCall(sub { close(*{$this->{handle}}) });
}
sub BINMODE 
{ 	my ($this) = @_;
	$this->parentCall(sub { binmode(*{$this->{handle}}) });
}

# Untie process is fully transparent for parent. For example, code:
#   tie(*STDOUT, "T1");
#   eval "use CGI::WebOut"; #***
#   print "OK!";
#   untie(*STDOUT);
# generates EXACTLY the same sequence of call to T1 class, as this 
# code without ***-marked line.
# Unfortunately we cannot retie CGI::WebOut::Tie back to the object
# in UNTIE() - when the sub finishes, Perl hardly remove tie. 
our $doNotUntie = 0;
sub UNTIE
{	my ($this, $nRef) = @_;
	return if $doNotUntie;
	my $handle = $this->{handle};
	CGI::WebOut::_Debug("UNTIE prev=%s, cur=%s", $this->{prevObj}, tied(*$handle));
	# Destroy output object BEFORE untie parent.
	$this->{outObj} = undef;
	# Untie parent object.
	if ($this->{prevObj}) {
		tieobj(*$handle, $this->{prevObj});
		$this->{prevObj} = undef; # release ref
		untie(*$handle); # call parent untie
		$this->{prevObj} = tied(*$handle);
	}
}

# void method parentPrint(...)
# Prints using parent print method.
sub parentPrint
{	my $this = shift;
	my $params = \@_;
	$this->parentCall(sub { print STDOUT @$params });
}

# void method parentCall($codeRef)
# Calls $codeRef in the context of object, previously tied to handle.
# After call context is switched back, as if nothing has happened.
# Returns the same that $codeRef had returned.
sub parentCall
{	my ($this, $sub) = @_;
	my ($handle, $obj) = ($this->{handle}, $this->{prevObj});
	my $save = tied(*$handle);
	if ($obj) {
		tieobj(*$handle, $obj) 
	} elsif ($save) {
		local $doNotUntie = 1;
		local $^W;
		untie(*$handle);
	}
	my @result = wantarray? $sub->() : scalar $sub->();
	if ($save) {
		tieobj(*$handle, $save);
	} elsif ($obj) {
		local $doNotUntie = 1;
		local $^W;
		untie(*$handle);
	}
	return wantarray? @result : $result[0];
}
}}}


# Since v2.0 AutoLoader is not used.
#use AutoLoader 'AUTOLOAD';
#return 1;
#__END__


# ������������� try-catch-throw:
# try { 
#   ���, ������� ����� �������� �� ������
#   ��� ������� ���������� ���������� � ������� throw
# } catch {
#   ��� ���������� ��� ��������� �� ������ - � $_
# } warnings {
#   ������ ������������ ������ � �������������� � @_
# }
# ����� catch � warnings ����������� � ������� �� ��������� � ����� �������������.
sub try (&;@) 
{	my ($try,@Hand) = @_;
	# �� �� ����� ������������ local ��� ���������� @Errors �� ��������� �������.
	# ���� � &$try ��������� ��������������, � ����� ����� ������ exit(),
	# �� �� ����� try() ���������� ��� � �� ������. ���� �� �� ������������ 
	# local, �� ��� �������������� � @Errors ���������� ��. ��� ��� ������������
	# ���������� �� ��������� ����������, �������������� � @Errors ��������� �� 
	# ����� � ��������� �� �����.
	my @SvErrors = @Errors;
	# ��������� try-����
	my @Result = eval { &$try };
	# ���������� ������ ����, ���� ������ ���� �� ���� ������ exit().
	# � ��������� ������ ��������� ����� �� ������� � �� ���������.
	# �������� ��� ��������� ��������������. ������ ���������� �� �
	# ���������� ���� local, ����� ��� ���������� ���� ����� ������ 
	# warnings-������� (��. ����).
	local @Warns = @Errors>@SvErrors? @Errors[@SvErrors..$#Errors] : ();
	# ��������������� ��������� �� �������
	@Errors = @SvErrors;
	# ��������� ����������� � ������� �� ���������
	map { &$_() } @Hand;
	# ���������� ��������, ������� ������ try-����
	return wantarray? @Result: $Result[0];
}

# ���������� �������-���������, ������� �������� ���� catch-�����.
sub catch(&;@) 
{	my ($body, @Hand)=@_;
	return (sub { if($@) { chomp($@); local $_=$@; &$body($_) } }, @Hand);
}

# ���������� �������-���������, ������� �������� ���� warnings-�����.
sub warnings(&;@) 
{	my ($body,@Hand)=@_;
	return (sub { &$body(@Warns) }, @Hand);
}

# ����������� ����������.
sub throw($) { 
	die(ref($_[0])? $_[0] : "$_[0]\n") 
}


# bool SetAutoflush([bool $mode])
# ������������� ����� ������ ������ echo: ���� $mode=1, �� ��������� ��� ��������� �����
# ������� ������ print ��� echo, ����� - ��������� (����� ������ ������������� �� Flush()).
# ���������� ���������� ������������� ����� ����������.
sub SetAutoflush(;$)
{	my ($mode)=@_;
	my $old = $UseAutoflush;
	if (defined $mode) { $UseAutoflush = $mode; }
	return $old;
}

# bool NoAutoflush()
# ��������� ���������� ����� ����� ������� echo.
# ���������� ���������� ������ ����������.
sub NoAutoflush() {
	return SetAutoflush(0);
}


# bool UseAutoflush()
# ��������� ���������� ����� ����� ������� echo.
# ���������� ���������� ������ ����������.
sub UseAutoflush() {
	return SetAutoflush(1);
}


# �������������� �� ������ URL (����� ���� ���������� ����������)
sub Redirect($)
{	my ($url) = @_;
	$Redirected = Header("Location: $url");
	exit;
}


# �������������� ������� �� ������ URL
sub ExternRedirect($)
{	my ($url) = @_;
	if ($url !~ /^\w+:/) {
		# ������������� �����.
		if ($url !~ m{^/}) {
			my $sn = $ENV{SCRIPT_NAME};
			$sn =~ s{/+[^/]*$}{}sg;
			$url = "$sn/$url";
		}
		# �������� ��� �����.
		$url = "http://$ENV{SERVER_NAME}$url";
	}
	$Redirected = Header("Location: $url");
	exit;
}


# ��������� ����������� ��������� ���������
sub NoCache()
{	return 1 if $NoCached++;
	Header("Expires: Mon, 26 Jul 1997 05:00:00 GMT") or return undef;
	Header("Last-Modified: ".gmtime(time)." GMT") or return undef;
	Header("Cache-Control: no-cache, must-revalidate") or return undef;
	Header("Pragma: no-cache") or return undef;
	return 1;
}


# int ErrorReporting([int $level])
# ������������� ����� ������ ������:
# 0 - ������ �� ���������
# 1 - ������ ��������� � �������
# 2 - ������ ��������� � ������� � ���� ������������
# ���� �������� �� �����, ����� �� ��������.
# ���������� ���������� ������ ������.
sub ErrorReporting(;$)
{	my ($lev)=@_;
	my $old = $ErrorReporting;
	$ErrorReporting = $lev if defined $lev;
	return $old;
}


# ��������� ��������� �� ������ � ������� ������.
sub Warning($)
{	my ($msg)=@_;
	push(@Errors, $msg);
}


# �������� ��� ������������ ��������� �� �������.
# ��� ������� ���������� � ������, ����� STDOUT ��������� � "�����������" ���������, 
# ������� ������������� print ���������!!!
sub __PrintAllErrors()
{	local $^W = undef;
	# http://forum.dklab.ru/perl/symbiosis/Fastcgi+WeboutUtechkaPamyati.html
	if(!@Errors || !$ErrorReporting){
		@Errors=(); 
        	return ; 
	}
	if (IsWebMode) {
		if ($ErrorReporting == ER_Err2Browser) {
			# ���� ��, ����� ��� ���� �������...
			echo "</script>","</table>"x6,"</pre>"x3,"</tt>"x2,"</i>"x2,"</b>"x2;
		}
		my %wasErr=();
		for (my $i=0; $i<@Errors; $i++) {
			chomp(my $st = $Errors[$i]); 
			# ��������� ������������� ��������� � ��������� �������.
			next if $wasErr{$st};
			$wasErr{$st}=1 if $st =~ /^Fatal:/;
			# ������� ���������.
			if ($ErrorReporting == ER_Err2Browser) {
				$st=~s/>/&gt;/sg;
				$st=~s/</&lt;/sg;
				$st=~s|^([a-zA-Z]+:)|<b>$1</b>|mgx;
				$st=~s|\n|<br>\n&nbsp;&nbsp;&nbsp;&nbsp;|g; 
				my $s=$i+1;
				for(my $i=length($s); $i<length(scalar(@Errors)); $i++) { $s="&nbsp;$s" }
        		echo "<b><tt>$s)</tt></b> $st<br>\n"; 
			} elsif ($ErrorReporting == ER_Err2Comment) {
        		echo "\n<!-- $st -->"; 
			} elsif ($ErrorReporting == ER_Err2Plain) {
        		echo "\n$st"; 
			}
		}
	} else {
		foreach my $st (@Errors) { chomp($st); echo "\n$st" }
	}
	@Errors=();
}

return 1;
__END__

=head1 NAME

CGI::WebOut - Perl extension to handle CGI output (in PHP-style).

=head1 SYNOPSIS

  # Simple CGI script (no 500 Apache error!)
  use CGI::WebOut;
  print "Hello world!"; # wow, we may NOT output Content-type!
  # Handle output for {}-block
  my $str=grab {
    print "Hi there!\n";
  };
  $str=~s/\n/<br>/sg;
  print $str;

=head1 DESCRIPTION

This module is used to make CGI programmer's work more comfortable. 
The main idea is to handle output stream (C<STDOUT>) to avoid any data 
to be sent to browser without C<Content-type> header. Of cource,
you may also send your own headers to browser using C<Header()>. Any 
errors or warnings in your script will be printed at the bottom of the page 
"in PHP-style". You may also use C<Carp> module together with C<CGI::WebOut>.

You may also handle any program block's output (using C<print> etc.)
and place it to the variable using C<grab {...}> subroutine. It is a 
very useful feature for lots of CGI-programmers.

The last thing - support of C<try-catch> "instruction". B<WARNING:> they 
are I<not> real instructions, like C<map {...}>, C<grep {...}> etc.! Be careful
with C<return> instruction in C<try-catch> blocks.

Note: you may use C<CGI::WebOut> outside the field of CGI scripting. In "non-CGI" 
script headers are NOT output, and warnings are shown as plain-text. 
C<grab {...}>, C<try-catch> etc. work as usual.

=head2 New features in version 2.0

Since version 2.0 module if fully tie-safe. That means the code:

  tie(*STDOUT, "T");
  eval "use CGI::WebOut";
  print "OK!";
  untie(*STDOUT);

generates I<exactly> the same sequense of T method calls as:

  tie(*STDOUT, "T");
  print "OK!";
  untie(*STDOUT);

So you can use CGI::WebOut with, for example, FastCGI module.

=head2 EXPORT

All the useful functions. Larry says it is not a good idea, 
but Rasmus does not think so.

=head1 EXAMPLES

  # Using Header()
  use CGI::WebOut;
  NoAutoflush();
  print "Hello world!"
  Header("X-Powered-by: dklab");

  # Handle output buffer
  use CGI::WebOut;
  my $str=grab {
    print "Hi there!\n";
	# Nested grab!
	my $s=grab {
		print "This string will be redirect to variable!";
	}
  }
  $str=~s/\n/<br>/sg;

  # Exception/warnings handle
  use CGI::WebOut;
  try {
    DoSomeDangerousStuff();
  } catch {
    print "An error occured: $_";
	throw "Error";
  } warnings {
    print "Wanning & error messages:".join("\n",@_);
  };



=head1 DESCRIPTION

=over 13

=item C<use CGI::WebOut [($forgotAboutHeaders)]>

Handles the C<STDOUT> to avoid document output without C<Content-type> header in "PHP-style". If C<$forgotAboutHeaders> is true, following "print" will produse output of all HTTP headers. Use this options only in FastCGI environment.


=item C<string grab { ... }>

Handles output stream. Usage:

    $grabbed = grab { 
        print 'Hello!' 
    } catch { 
        die "An error occurred while grabbing the output: $@"; 
    };

or simply

    $grabbed = grab { print 'Hello!' };


=item C<bool try {...} catch {...} warnings {...}>

Try-catch preudo-instruction. Usage:

    try { 
       some dangeorus code, which may call die() or
       any other bad function (or throw "instruction")
    } catch {
       use $_ to get the exception or error message
    } warnings {
       use @_ to get all the warning messages
    }

Note: C<catch> and C<warnings> blocks are optional and called in 
order of their appearance.


=item C<void throw($exception_object)>

Throws an exception.

=item C<int ErrorReporting([int $level])>

Sets the error handling mode. C<$level> may be:

    ER_NoErr       - no error reporting;
    ER_Err2Browser - errors are printed to browser;
    ER_Err2Comment - errors are printed to browser inside <!-- ... -->;
    ER_Err2Plain   - plain-text warnings.

Returns the previous error reporting mode.


=item C<void Header(string $header)>

Sets document responce header. If autoflush mode is not set, this 
function may be used just I<before> the first output.


=item C<int SetAutoflush([bool $mode])>

Sets the autoflush mode (C<$mode>!=0) or disables if (C<$mode>=0). Returns the
previous status of autoflush mode.


=item C<int NoAutoflush()>

Equivalents to C<SetAutoflush(0)>.


=item C<int UseAutoflush()>

Equivalents to C<SetAutoflush(1)>.


=item C<void Flush()>

Flushes the main output buffer to browser. If autoflush mode is set,
this function is called automatically after each C<print> call.


=item C<void Redirect(string $URL)>

Sends C<Location: $URL> header to redirect the browser to C<$URL>. Also finishes the script with C<exit()> call.


=item C<void ExternRedirect(string $URL)>

The same as C<Redirect()>, but first translates C<$URL> to absolute format: "http://host/url".


=item C<void NoCache()>

Disables browser document caching.

=back

=head1 AUTHOR

Dmitry Koteroff <dmitry@koteroff.ru>, http://dklab.ru/chicken/4.html

=head1 SEE ALSO

C<CGI::WebIn>, C<Carp>.

=cut
