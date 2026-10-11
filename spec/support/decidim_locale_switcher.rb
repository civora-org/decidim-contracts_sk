# frozen_string_literal: true

# Switches the harness stand-in's copy of the REAL Decidim::LocaleSwitcher on
# for the examples tagged :decidim_locale_switcher (see the "DummyLocaleSwitching"
# block in spec/dummy/config/application.rb). With it on, a request's locale is
# detected like in a host (?locale=, session, Accept-Language) and
# default_url_options is the pinned Decidim line's own: 0.31 adds `?locale=`
# for a non-default locale only, 0.32 adds it always.
RSpec.configure do |config|
  config.around(:each, :decidim_locale_switcher) do |example|
    DummyLocaleSwitching.enabled = true
    example.run
  ensure
    DummyLocaleSwitching.enabled = false
  end
end
