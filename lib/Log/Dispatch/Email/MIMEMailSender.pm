package Log::Dispatch::Email::MIMEMailSender;

use Modern::Perl;

our $VERSION = '0.2';

# use Log::Dispatch::Types;

# use Specio;
# use Specio::Declare;
# use Specio::Library::Builtins;

use Email::MIME;
use Email::Simple;
use Email::Sender::Simple;
# use Email::Simple::Creator; # ??? Probably don't need this
use Email::Sender::Transport::SMTP;
use File::Basename;
use Log::Log4perl::MDC;
use Try::Tiny;
use Params::ValidationCompiler qw( validation_for );

# @TODO parent?
use base qw( Log::Dispatch::Email );

{
    my $validator_params = {
        smtp_host => { default => 'localhost' },
        smtp_port => { default => 25 },
        reply_to => 0,
        cc => 0,
    };
    my $validator = validation_for(
        params => $validator_params,
        slurpy => 1,
    );

    sub new {
        my $class = shift;
        my %p = $validator->(@_);

        my %params = map { $_ => delete $p{$_} } keys %{$validator_params};
        my $self = $class->SUPER::new(%p);
        foreach my $key (keys %params) {
            $self->{$key} = $params{$key};
        }

        return $self;
    }
}

sub send_email {
    my $self = shift;
    my %p = @_;

    my $to = Log::Log4perl::MDC->get('to');
    my @to;
    @to = $to ? (ref($to) eq 'ARRAY' ? @{$to} : ($to)) : @{$self->{to}};

    my @header = (
        'To' => ( join ',', @to ),
        'From' => $self->{from},
    );

    push @header, 'Subject' => Log::Log4perl::MDC->get('subject') // $self->{subject};
    push @header, 'Reply-To' => $self->{reply_to} if $self->{reply_to};
    push @header, 'cc' => $self->{cc} if $self->{cc};

    # @TODO: Would be quite easy to autodetect content type and support multiple files
    my $mail;
    if (
        Log::Log4perl::MDC->get('attachment-file') ||
        Log::Log4perl::MDC->get('attachment-data')
    ) {
        # TODO: Should have some more validation
        # that attachment is a path and file exists
        # plus we take this from the context thingy, not class param

        my $attachment_body;
        my $attachment_filename;

        $attachment_filename = Log::Log4perl::MDC->get('attachment-filename');
        if (Log::Log4perl::MDC->get('attachment-file')) {
            my $attachment_file = Log::Log4perl::MDC->get('attachment-file');
            {
                local $/ = undef;
                open(FILE, $attachment_file, '<');
                binmode FILE;
                ($attachment_filename) = fileparse($attachment_file) unless $attachment_filename;
                $attachment_body = <FILE>;
                close(FILE);
            }
        }
        elsif (Log::Log4perl::MDC->get('attachment-data')) {
            $attachment_body = Log::Log4perl::MDC->get('attachment-data');
            $attachment_filename = 'attachment' unless $attachment_filename;
        }

        $mail = Email::MIME->create(
            header => \@header,
            parts => [
                Email::MIME->create(
                    body_str => $p{message},
                    attributes =>  {
                        charset => Log::Log4perl::MDC->get('charset') // 'utf-8',
                        content_type => Log::Log4perl::MDC->get('content-type') // 'text/plain',
                        encoding => Log::Log4perl::MDC->get('encoding') // 'quoted-printable',
                    }
                ),
                Email::MIME->create(
                    body => $attachment_body,
                    attributes => {
                        filename => $attachment_filename,
                        name => $attachment_filename, #??
                        content_type => Log::Log4perl::MDC->get('attachment-content-type') // 'text/plain',
                        encoding => Log::Log4perl::MDC->get('attachment-encoding') // 'base64',
                        disposition => Log::Log4perl::MDC->get('attachment-disposition') // 'attachment',
                    },
                ),
            ]
        );
    }
    else {
        $mail = Email::Simple->create(
            header => \@header,
            body => $p{message},
        );
    }

    # TODO: SMTP authentication params
    my $transport = Email::Sender::Transport::SMTP->new(
        {
            host => $self->{smtp_host},
            port => $self->{smtp_port},
        }
    );

    Email::Sender::Simple->send($mail, { transport => $transport });
}

1;
