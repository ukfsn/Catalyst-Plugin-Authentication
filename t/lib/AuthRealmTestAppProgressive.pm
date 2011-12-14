package AuthRealmTestAppProgressive;
use warnings;
use strict;
use base qw/Catalyst/;

### using A::Store::minimal with new style realms
### makes the app blow up, since c::p::a::s::minimal
### isa c:a::s::minimal, and it's compat setup() gets
### run, with an unexpected config has (realms on top,
### not users). This tests makes sure the app no longer
### blows up when this happens.
use Catalyst qw/
    Authentication
    Authentication::Store::Minimal
/;

our %members = (
    'members' => {
        bob => { password => "s00p3r" }
    },
    'other' => {
        sally => { password => "s00p3r" }
    },
);

# Matches user above so we can test against a detach and confirm
# it gets skipped and auths in 'members' realm
our $detach_test_info = {
    'user' => 'bob',
    'password' => 's00p3r',
    'realm_to_pass' => 'members',
};

__PACKAGE__->config('Plugin::Authentication' => {
    default_realm => 'progressive',
    progressive => {
        class  => 'Progressive',
        realms => [ 'alwaysdetach', 'other', 'members' ],
    },
    alwaysdetach => {
        credential => {
            class => 'AlwaysDetach',
        },
        store => {
            class => 'Minimal',
            users => {},
        },
    },
    other => {
        credential => {
            class => 'Password',
            password_field => 'password',
            password_type  => 'clear'
        },
        store => {
            class => 'Minimal',
            users => $members{other},
        }
    },
    members => {
        credential => {
            class => 'Password',
            password_field => 'password',
            password_type => 'clear'
        },
        store => {
            class => 'Minimal',
            users => $members{members},
        }
    },
});

__PACKAGE__->setup;

1;

