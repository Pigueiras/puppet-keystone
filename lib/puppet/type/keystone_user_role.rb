# LP#1408531
File.expand_path('../..', File.dirname(__FILE__)).tap { |dir| $LOAD_PATH.unshift(dir) unless $LOAD_PATH.include?(dir) }
File.expand_path('../../../../openstacklib/lib', File.dirname(__FILE__)).tap { |dir| $LOAD_PATH.unshift(dir) unless $LOAD_PATH.include?(dir) }

require 'puppet/provider/keystone/util'
require 'puppet_x/keystone/composite_namevar'
require 'puppet_x/keystone/type'

Puppet::Type.newtype(:keystone_user_role) do

  desc <<-EOT
    This is currently used to model the creation of keystone users
    roles.

    User roles are an assignment of a role to a user on a certain
    tenant. The combination of all of these attributes is unique.

    The resource's name can be specified like this:

     <user(::user_domain)?>@<project(::project_domain)?|::domain>

    which means the user is required.  Project and domain are mutually
    exclusive.  User_domain and project_domain are optional.

    "user_domain" and "project_domain" resources default to the name
    of the "Keystone_domain" resource which has the "is_default"
    property set to true in the current catalog, or to "Default" if
    such resource doesn't exist in the catalog.

  EOT

  include PuppetX::Keystone::CompositeNamevar::Helpers
  ensurable

  newparam(:name, :namevar => true)

  [:user, :project].each do |p|
    newparam(p) do
      isnamevar
      defaultto PuppetX::Keystone::CompositeNamevar::Unset
    end
  end

  [:user_domain, :project_domain].each do |p|
    newparam(p) do
      isnamevar
      include PuppetX::Keystone::Type::DefaultDomain
    end
  end

  newparam(:domain) do
    isnamevar
    defaultto PuppetX::Keystone::CompositeNamevar::Unset
    validate do |v|
      if !resource.parameters[:project].nil? &&
          resource.parameters[:project].value != PuppetX::Keystone::CompositeNamevar::Unset &&
          v != PuppetX::Keystone::CompositeNamevar::Unset
        raise(Puppet::ResourceError,
              'Cannot define both project and domain for a role.')
      end
    end
  end

  newparam(:system) do
    isnamevar
    defaultto PuppetX::Keystone::CompositeNamevar::Unset
    validate do |v|
      if !resource.parameters[:project].nil? &&
          resource.parameters[:project].value != PuppetX::Keystone::CompositeNamevar::Unset &&
          v != PuppetX::Keystone::CompositeNamevar::Unset
        raise(Puppet::ResourceError,
              'Cannot define both project and system for a role.')
      end
      if !resource.parameters[:domain].nil? &&
          resource.parameters[:domain].value != PuppetX::Keystone::CompositeNamevar::Unset &&
          v != PuppetX::Keystone::CompositeNamevar::Unset
        raise(Puppet::ResourceError,
              'Cannot define both domain and scope for a role.')
      end
    end
  end

  newproperty(:roles,  :array_matching => :all) do
    def insync?(is)
      return false unless is.is_a? Array
      # order of roles does not matter
      is.sort == should.sort
    end
  end

  autorequire(:keystone_user) do
    # Pass through title parsing for matching resource.
    [provider.class.resource_to_name(self[:user_domain], self[:user], false)]
  end

  autorequire(:keystone_tenant) do
    rv = []
    if parameter_set?(:project)
      # Pass through title parsing for matching resource.
      rv << provider.class.resource_to_name(self[:project_domain],
                                            self[:project], false)
    end
    rv
  end

  autorequire(:keystone_role) do
    self[:roles]
  end

  autorequire(:keystone_domain) do
    default_domain = catalog.resources.find do |r|
      r.class.to_s == 'Puppet::Type::Keystone_domain' &&
        r[:is_default] == :true &&
        r[:ensure] == :present
    end
    rv = [self[:user_domain]]
    if parameter_set?(:domain)
      rv << self[:domain]
    elsif parameter_set?(:project)
      rv << self[:project_domain]
    end
    # Only used to display the deprecation warning.
    rv << default_domain.name   unless default_domain.nil?
    rv
  end

  # we should not do anything until the keystone service is started
  autorequire(:anchor) do
    ['keystone::service::end']
  end

  def self.title_patterns
    user = PuppetX::Keystone::CompositeNamevar.not_two_colon_regex
    project_domain = user
    domain = user
    system = user
    user_domain = Regexp.new(/(?:[^:@]|:[^:@])+/)
    project = user_domain
    [
      [
        # fully qualified user with fully qualified project
        /^(#{user})::(#{user_domain})@(#{project})::(#{project_domain})$/,
        [
          [:user],
          [:user_domain],
          [:project],
          [:project_domain]
        ]
      ],
      # fully qualified user with domain
      [
        /^(#{user})::(#{user_domain})@::(#{domain})$/,
        [
          [:user],
          [:user_domain],
          [:domain]
        ]
      ],
      # fully qualified user with project
      [
        /^(#{user})::(#{user_domain})@(#{project})$/,
        [
          [:user],
          [:user_domain],
          [:project]
        ]
      ],
      # user with fully qualified project
      [
        /^(#{user})@(#{project})::(#{project_domain})$/,
        [
          [:user],
          [:project],
          [:project_domain]
        ]
      ],
      # user with domain
      [
        /^(#{user})@::(#{domain})$/,
        [
          [:user],
          [:domain]
        ]
      ],
      # user with project
      [
        /^(#{user})@(#{project})$/,
        [
          [:user],
          [:project]
        ]
      ],
      # fully qualified user
      [
        /^(#{user})::(#{user_domain})@::::(#{system})$/,
        [
          [:user],
          [:user_domain],
          [:system]
        ]
      ],
      # user
      [
        /^(#{user})@::::(#{system})$/,
        [
          [:user],
          [:system]
        ]
      ]
    ]
  end
end
