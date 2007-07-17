#!/usr/bin/perl

package Catalyst::Plugin::Authentication::Credential::Password;

use strict;
use warnings;

use Scalar::Util        ();
use Catalyst::Exception ();
use Digest              ();

sub new {
    my ($class, $config, $app) = @_;
    
    my $self = { %{$config} };
    $self->{'password_field'} ||= 'password';
    $self->{'password_type'}  ||= 'clear';
    $self->{'password_hash_type'} ||= 'SHA-1';
    
    if (!grep /$$self{'password_type'}/, ('clear', 'hashed', 'salted_hash', 'crypted', 'self_check')) {
        Catalyst::Exception->throw(__PACKAGE__ . " used with unsupported password type: " . $self->{'password_type'});
    }

    bless $self, $class;
}

sub authenticate {
    my ( $self, $c, $authstore, $authinfo ) = @_;

    my $user_obj = $authstore->find_user($authinfo, $c);
    if (ref($user_obj)) {
        if ($self->check_password($user_obj, $authinfo)) {
            return $user_obj;
        }
    } else {
        $c->log->debug("Unable to locate user matching user info provided");
        return;
    }
}

sub check_password {
    my ( $self, $user, $authinfo ) = @_;
    
    if ($self->{'password_type'} eq 'self_check') {
        return $user->check_password($authinfo->{$self->{'password_field'}});
    } else {
        my $password = $authinfo->{$self->{'password_field'}};
        my $storedpassword = $user->get($self->{'password_field'});
        
        if ($self->{password_type} eq 'clear') {
            return $password eq $storedpassword;
        }  elsif ($self->{'password_type'} eq 'crypted') {            
            return $storedpassword eq crypt( $password, $storedpassword );
        } elsif ($self->{'password_type'} eq 'salted_hash') {
            require Crypt::SaltedHash;
            my $salt_len = $self->{'password_salt_len'} ? $self->{'password_salt_len'} : 0;
            return Crypt::SaltedHash->validate( $storedpassword, $password,
                $salt_len );
        } elsif ($self->{'password_type'} eq 'hashed') {

             my $d = Digest->new( $self->{'password_hash_type'} );
             $d->add( $self->{'password_pre_salt'} || '' );
             $d->add($password);
             $d->add( $self->{'password_post_salt'} || '' );

             my $computed    = $d->clone()->digest;
             my $b64computed = $d->clone()->b64digest;
             return ( ( $computed eq $storedpassword )
                   || ( unpack( "H*", $computed ) eq $storedpassword )
                   || ( $b64computed eq $storedpassword)
                   || ( $b64computed.'=' eq $storedpassword) );
        }
    }
}

## BACKWARDS COMPATIBILITY - all subs below here are deprecated 
## They are here for compatibility with older modules that use / inherit from C::P::A::Password 
## login()'s existance relies rather heavily on the fact that Credential::Password
## is being used as a credential.  This may not be the case.  This is only here 
## for backward compatibility.  It will go away in a future version
## login should not be used in new applications.

sub login {
    my ( $c, $user, $password, @rest ) = @_;
    
    unless (
        defined($user)
            or
        $user = $c->request->param("login")
             || $c->request->param("user")
             || $c->request->param("username")
    ) {
        $c->log->debug(
            "Can't login a user without a user object or user ID param")
              if $c->debug;
        return;
    }

    unless (
        defined($password)
            or
        $password = $c->request->param("password")
                 || $c->request->param("passwd")
                 || $c->request->param("pass")
    ) {
        $c->log->debug("Can't login a user without a password")
          if $c->debug;
        return;
    }
    
    unless ( Scalar::Util::blessed($user)
        and $user->isa("Catalyst::Plugin::Authentication::User") )
    {
        if ( my $user_obj = $c->get_user( $user, $password, @rest ) ) {
            $user = $user_obj;
        }
        else {
            $c->log->debug("User '$user' doesn't exist in the default store")
              if $c->debug;
            return;
        }
    }

    if ( $c->_check_password( $user, $password ) ) {
        $c->set_authenticated($user);
        $c->log->debug("Successfully authenticated user '$user'.")
          if $c->debug;
        return 1;
    }
    else {
        $c->log->debug(
            "Failed to authenticate user '$user'. Reason: 'Incorrect password'")
          if $c->debug;
        return;
    }
    
}

## also deprecated.  Here for compatibility with older credentials which do not inherit from C::P::A::Password
sub _check_password {
    my ( $c, $user, $password ) = @_;
    
    if ( $user->supports(qw/password clear/) ) {
        return $user->password eq $password;
    }
    elsif ( $user->supports(qw/password crypted/) ) {
        my $crypted = $user->crypted_password;
        return $crypted eq crypt( $password, $crypted );
    }
    elsif ( $user->supports(qw/password hashed/) ) {

        my $d = Digest->new( $user->hash_algorithm );
        $d->add( $user->password_pre_salt || '' );
        $d->add($password);
        $d->add( $user->password_post_salt || '' );

        my $stored      = $user->hashed_password;
        my $computed    = $d->clone()->digest;
        my $b64computed = $d->clone()->b64digest;

        return ( ( $computed eq $stored )
              || ( unpack( "H*", $computed ) eq $stored )
              || ( $b64computed eq $stored)
              || ( $b64computed.'=' eq $stored) );
    }
    elsif ( $user->supports(qw/password salted_hash/) ) {
        require Crypt::SaltedHash;

        my $salt_len =
          $user->can("password_salt_len") ? $user->password_salt_len : 0;

        return Crypt::SaltedHash->validate( $user->hashed_password, $password,
            $salt_len );
    }
    elsif ( $user->supports(qw/password self_check/) ) {

        # while somewhat silly, this is to prevent code duplication
        return $user->check_password($password);

    }
    else {
        Catalyst::Exception->throw(
                "The user object $user does not support any "
              . "known password authentication mechanism." );
    }
}

__PACKAGE__;

__END__

=pod

=head1 NAME

Catalyst::Plugin::Authentication::Credential::Password - Authenticate a user
with a password.

=head1 SYNOPSIS

    use Catalyst qw/
      Authentication
      /;

    package MyApp::Controller::Auth;

    sub login : Local {
        my ( $self, $c ) = @_;

        $c->authenticate( { username => $c->req->param('username'),
                            password => $c->req->param('password') });
    }

=head1 DESCRIPTION

This authentication credential checker takes authentication information
(most often a username) and a password, and attempts to validate the password
provided against the user retrieved from the store.

=head1 CONFIGURATION

    # example
    __PACKAGE__->config->{authentication} = 
                {  
                    default_realm => 'members',
                    realms => {
                        members => {
                            
                            credential => {
                                class => 'Password',
                                password_field => 'password',
                                password_type => 'hashed',
                                password_hash_type => 'SHA-1'                                
                            },    
                            ...


The password module is capable of working with several different password
encryption/hashing algorithms. The one the module uses is determined by the
credential configuration.

=over 4 

=item class 

The classname used for Credential. This is part of
L<Catalyst::Plugin::Authentication> and is the method by which
Catalyst::Plugin::Authentication::Credential::Password is loaded as the
credential validator. For this module to be used, this must be set to
'Password'.

=item password_field

The field in the user object that contains the password. This will vary
depending on the storage class used, but is most likely something like
'password'. In fact, this is so common that if this is left out of the config,
it defaults to 'password'. This field is obtained from the user object using
the get() method. Essentially: $user->get('passwordfieldname');

=item password_type 

This sets the password type.  Often passwords are stored in crypted or hashed
formats.  In order for the password module to verify the plaintext password 
passed in, it must be told what format the password will be in when it is retreived
from the user object. The supported options are:

=over 8

=item clear

The password in user is in clear text and will be compared directly.

=item self_check

This option indicates that the password should be passed to the check_password()
routine on the user object returned from the store.  

=item crypted

The password in user is in UNIX crypt hashed format.  

=item salted_hash

The password in user is in salted hash format, and will be validated
using L<Crypt::SaltedHash>.  If this password type is selected, you should
also provide the B<password_salt_len> config element to define the salt length.

=item hashed

If the user object supports hashed passwords, they will be used in conjunction
with L<Digest>. The following config elements affect the hashed configuration:

=over 8

=item password_hash_type 

The hash type used, passed directly to L<Digest/new>.  

=item password_pre_salt 

Any pre-salt data to be passed to L<Digest/add> before processing the password.

=item password_post_salt

Any post-salt data to be passed to L<Digest/add> after processing the password.

=back

=back

=back

=head1 USAGE

The Password credential module is very simple to use.  Once configured as indicated
above, authenticating using this module is simply a matter of calling $c->authenticate()
with an authinfo hashref that includes the B<password> element.  The password element should
contain the password supplied by the user to be authenticated, in clear text.  The other
information supplied in the auth hash is ignored by the Password module, and simply passed
to the auth store to be used to retrieve the user.  An example call follows:

    if ($c->authenticate({ username => $username,
                           password => $password} )) {
        # authentication successful
    } else {
        # authentication failed
    }

=head1 METHODS

There are no publicly exported routines in the Password module (or indeed in
most credential modules.)  However, below is a description of the routines 
required by L<Catalyst::Plugin::Authentication> for all credential modules.

=over 4

=item new ( $config, $app )

Instantiate a new Password object using the configuration hash provided in
$config. A reference to the application is provided as the second argument.
Note to credential module authors: new() is called during the application's
plugin setup phase, which is before the application specific controllers are
loaded. The practical upshot of this is that things like $c->model(...) will
not function as expected.

=item authenticate ( $authinfo, $c )

Try to log a user in, receives a hashref containing authentication information
as the first argument, and the current context as the second.

=back
