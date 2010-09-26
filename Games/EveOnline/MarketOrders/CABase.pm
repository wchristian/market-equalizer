package Games::EveOnline::MarketOrders::CABase;
use base 'CGI::Application';
use lib '../../..';

use vars '$VERSION';
$VERSION = '1.00';

# Just load a few recommended plugins by default. 
#use CGI::Application::Plugin::AutoRunmode;
use CGI::Application::Plugin::Forward;
use CGI::Application::Plugin::Redirect;
use CGI::Application::Plugin::Session;
use CGI::Application::Plugin::ValidateRM; 
use CGI::Application::Plugin::ConfigAuto 'cfg';
use CGI::Application::Plugin::FillInForm 'fill_form';
#use CGI::Application::Plugin::ErrorPage  'error';
use CGI::Application::Plugin::Stream     'stream_file';
use CGI::Application::Plugin::DBH 		  qw(dbh_config dbh); 
use CGI::Application::Plugin::LogDispatch;
use CGI::Application::Plugin::TT;
use CGI::Application::Plugin::ActionDispatch;
use CGI::Application::Plugin::Phrasebook;

# For development, need to activated with an ENV variable. 
use CGI::Application::Plugin::DebugScreen;
use Games::EveOnline::MarketOrders::DevPopup;
use CGI::Application::Plugin::DevPopup::HTTPHeaders;
use CGI::Application::Plugin::DevPopup::Timing;
use CGI::Application::Standard::Config;





1;
