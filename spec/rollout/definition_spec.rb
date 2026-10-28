require "spec_helper"
require "tmpdir"

RSpec.describe "Rollout.definitions" do
  around do |example|
    Dir.mktmpdir do |dir|
      @dir = dir
      example.run
    end
  end

  after do
    Rollout.send(:remove_instance_variable, :@definitions_path) if Rollout.instance_variable_defined?(:@definitions_path)
  end

  def write(name, content)
    File.write(File.join(@dir, name), content)
  end

  it "loads each .yml file directly in the folder, named after the file" do
    write("chat.yml", "description: Group chat.\ncache: user\n")
    write("notes.yaml", "description: Not loaded.\n")
    FileUtils.mkdir_p(File.join(@dir, "drafts"))
    write("drafts/inbox.yml", "description: Not loaded.\n")
    Rollout.definitions_path = @dir

    chat = Rollout.definitions.fetch(:chat)

    expect(Rollout.definitions.keys).to eq [:chat]
    expect(chat.description).to eq "Group chat."
    expect(chat.attributes).to eq("description" => "Group chat.", "cache" => "user")
    expect(chat.path).to eq File.join(@dir, "chat.yml")
  end

  it "defaults to config/rollouts under the current directory" do
    folder = File.join(@dir, "config", "rollouts")
    FileUtils.mkdir_p(folder)
    File.write(File.join(folder, "chat.yml"), "description: Group chat.\n")

    Dir.chdir(@dir) do
      expect(Rollout.definitions.keys).to eq [:chat]
    end
  end

  it "picks up a file added after an earlier call" do
    Rollout.definitions_path = @dir
    expect(Rollout.definitions).to eq({})

    write("chat.yml", "description: Group chat.\n")
    expect(Rollout.definitions.keys).to eq [:chat]
  end

  it "takes brackets in the folder's path literally" do
    folder = File.join(@dir, "rollouts[1]")
    FileUtils.mkdir_p(folder)
    File.write(File.join(folder, "chat.yml"), "description: Group chat.\n")
    Rollout.definitions_path = folder

    expect(Rollout.definitions.keys).to eq [:chat]
  end

  it "has no definitions when the folder is missing or the path is nil" do
    Rollout.definitions_path = File.join(@dir, "missing")
    expect(Rollout.definitions).to eq({})

    Rollout.definitions_path = nil
    expect(Rollout.definitions).to eq({})
  end

  it "names the file that is not valid YAML" do
    write("chat.yml", "description: [unclosed\n")
    Rollout.definitions_path = @dir

    expect { Rollout.definitions }.to raise_error(Rollout::InvalidDefinition, /chat\.yml/)
  end

  it "rejects a description that is not a string" do
    write("chat.yml", "description: 42\n")
    Rollout.definitions_path = @dir

    expect { Rollout.definitions }.to raise_error(Rollout::InvalidDefinition, /description must be a string/)
  end
end
