require "json"
require "shellwords"

# One configuration source for archive identity, profile mapping and upload validation.
class ReleaseConfig
  attr_reader :bundle_id, :team_id, :version, :build_number, :profile_name, :output, :app_store_app_id
  def initialize(env = ENV)
    defaults = JSON.parse(File.read(File.expand_path("../Release.json", __dir__)))
    @bundle_id = env.fetch("CMUX_REMOTE_IOS_BUNDLE_ID", defaults.fetch("bundle_id"))
    @team_id = env.fetch("CMUX_REMOTE_IOS_TEAM_ID", defaults.fetch("team_id"))
    @version = env.fetch("CMUX_REMOTE_IOS_VERSION", defaults.fetch("version"))
    @build_number = env.fetch("CMUX_REMOTE_IOS_BUILD_NUMBER") { raise "Set CMUX_REMOTE_IOS_BUILD_NUMBER to a new positive build number" }
    @profile_name = env.fetch("CMUX_REMOTE_IOS_PROFILE_NAME", defaults.fetch("profile_name"))
    @keychain = env["CMUX_REMOTE_IOS_KEYCHAIN_PATH"]
    @app_store_app_id = env["CMUX_REMOTE_IOS_APP_STORE_APP_ID"].to_s
    @app_store_app_id = defaults["app_store_app_id"].to_s if @app_store_app_id.empty?
    @output = File.expand_path(env.fetch("CMUX_REMOTE_IOS_OUTPUT", "../../.build/ios-release"), __dir__)
    raise "Invalid or unrelated bundle identity" unless @bundle_id.match?(/\Acom\.st0newan9\.cmux-remote(?:\.[A-Za-z0-9-]+)*\z/)
    raise "Invalid Apple team" unless @team_id.match?(/\A[A-Z0-9]{10}\z/)
    raise "Invalid version" unless @version.match?(/\A\d+\.\d+\.\d+\z/)
    raise "Invalid build number" unless @build_number.match?(/\A[1-9]\d{0,8}\z/)
    raise "Invalid profile name" if @profile_name.empty? || @profile_name.match?(/[\x00-\x1f]/)
    raise "Invalid App Store app ID" unless @app_store_app_id.empty? || @app_store_app_id.match?(/\A[1-9]\d*\z/)
  end
  def xcargs
    args = ["DEVELOPMENT_TEAM=#{team_id}", "PRODUCT_BUNDLE_IDENTIFIER=#{bundle_id}",
     "MARKETING_VERSION=#{version}", "CURRENT_PROJECT_VERSION=#{build_number}",
     "CODE_SIGN_STYLE=Manual", "CODE_SIGN_IDENTITY=Apple Distribution",
     "PROVISIONING_PROFILE_SPECIFIER=#{profile_name}"]
    args << "OTHER_CODE_SIGN_FLAGS=#{['--keychain', @keychain].shelljoin}" unless @keychain.to_s.empty?
    args.shelljoin
  end
  def export_options
    { method: "app-store", signingStyle: "manual", teamID: team_id,
      provisioningProfiles: { bundle_id => profile_name }, compileBitcode: false }
  end
end
