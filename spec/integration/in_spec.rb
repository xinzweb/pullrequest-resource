require 'spec_helper'
require 'json'
require 'tmpdir'

describe 'get' do
  let(:proxy) { Billy::Proxy.new }
  let(:dest_dir) { Dir.mktmpdir }
  let(:git_dir)  { Dir.mktmpdir }
  let(:git_uri)  { "file://#{git_dir}" }

  before { proxy.start }
  after  { proxy.reset }

  def git(cmd, dir = git_dir)
    Dir.chdir(dir) { `git #{cmd}`.chomp }
  end

  def commit(msg)
    git("-c user.name='test' -c user.email='test@example.com' commit -q --allow-empty -m '#{msg}'")
    git('log --format=format:%H HEAD')
  end

  before do
    proxy.stub('https://api.github.com:443/repos/jtarchie/test/pulls/1')
         .and_return(json: { html_url: 'http://example.com', number: 1, head: { ref: 'foo' } })

    git('init -q')
    @ref = commit('init')
    commit('second')

    git("update-ref refs/pull/1/head #{@ref}")
  end

  it 'checks out the pull request to dest_dir' do
    get(version: { ref: @ref, pr: '1' }, source: { access_token: 'abc', uri: git_uri, repo: 'jtarchie/test' })
    expect(@ref).to eq git('log --format=format:%H HEAD', dest_dir)
  end

  it 'returns the correct JSON metadata' do
    output, = get(version: { ref: @ref, pr: '1' }, source: { uri: git_uri, repo: 'jtarchie/test' })
    expect(output).to eq('version'  => { 'ref' => @ref, 'pr' => '1' },
                         'metadata' => [{
                           'name' => 'url',
                           'value' => 'http://example.com'
                         }])
  end

  it 'adds metadata to `git config`' do
    get(version: { ref: @ref, pr: '1' }, source: { uri: git_uri, repo: 'jtarchie/test' })

    value = git('config --get pullrequest.url', dest_dir)
    expect(value).to eq 'http://example.com'
  end

  it 'checks out as a branch' do
    get(version: { ref: @ref, pr: '1' }, source: { uri: git_uri, repo: 'jtarchie/test' })

    value = git('rev-parse --abbrev-ref HEAD', dest_dir)
    expect(value).to eq 'pr_temp_branch'
  end

  it 'sets config variable to branch name' do
    get(version: { ref: @ref, pr: '1' }, source: { uri: git_uri, repo: 'jtarchie/test' })
    value = git('config pullrequest.branch', dest_dir)
    expect(value).to eq 'pr_temp_branch'
  end

  context 'when the git clone fails' do
    it 'provides a helpful erorr message' do
      _, error = get(version: { ref: @ref, pr: '1' }, source: { uri: 'invalid_git_uri', repo: 'jtarchie/test' })
      expect(error).to include 'git clone failed'
    end
  end

  context 'when `every` is not defined' do
    it 'shows a deprecation warning' do
      _, error = get(version: { ref: @ref, pr: '1' }, source: { uri: git_uri, repo: 'jtarchie/test' })
      expect(error).to include 'DEPRECATION: Please note that you should update to using `version: every` on your `get` for this resource.'
    end
  end
end
