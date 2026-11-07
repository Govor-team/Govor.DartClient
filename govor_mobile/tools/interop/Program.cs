using System.Text;
using System.Text.Json;
using Govor.Application.Authentication;
using Govor.Application.E2ee;
using SecureRemotePassword;
  
// ONLY public test material. Never use these fixture keys in a real account.
var options = new JsonSerializerOptions { WriteIndented = true };
if (args.Length == 2 && args[0] == "verify")
{
    using var data = JsonDocument.Parse(File.ReadAllText(args[1]));
    var root = data.RootElement;
    var dartKeys = root.GetProperty("Keys").Deserialize<DevicePrivateKeys>()!;
    var dartMessage = root.GetProperty("Message").GetString()!;
    var env = E2eeProtocol.Verify(dartMessage);
    var plain = E2eeProtocol.Decrypt(dartMessage, dartKeys, env.MessageId, env.ConversationId, 0, env.Sender.UserId);
    if (plain.Text != "Привет из Flutter 🔐") throw new Exception("Text mismatch");
    var dartVault = root.GetProperty("Vault").Deserialize<RecoveryVault>()!;
    if (E2eeRecoveryProtocol.Open(dartVault, dartVault.UserId, root.GetProperty("Code").GetString()!) != "flutter archive") throw new Exception("Archive mismatch");
    Console.WriteLine(".NET verified Dart ES256/certificate/RSA-OAEP-256/A256GCM message and recovery vault.");
    return;
}
var user = Guid.Parse("11111111-1111-4111-8111-111111111111");
var sessionId = Guid.Parse("22222222-2222-4222-8222-222222222222");
var conversation = Guid.Parse("33333333-3333-4333-8333-333333333333");
var messageId = Guid.Parse("44444444-4444-4444-8444-444444444444");
var password = "тестовый пароль 🔐";
var salt = Convert.ToHexString(Enumerable.Range(0, 32).Select(i => (byte)i).ToArray());
var identity = Convert.ToHexString(Enumerable.Range(32, 32).Select(i => (byte)i).ToArray());
var derived = PasswordProtocol.Derive(password, salt, identity);
var client = PasswordProtocol.Client();
var x = client.DerivePrivateKey(salt, identity, derived.Secret);
var verifier = client.DeriveVerifier(x);
var ephemeral = client.GenerateEphemeral();
var server = PasswordProtocol.Server();
var remote = server.GenerateEphemeral(verifier);
var proof = client.DeriveSession(ephemeral.Secret, remote.Public, salt, identity, x);
var serverProof = server.DeriveSession(remote.Secret, ephemeral.Public, salt, identity, verifier, proof.Proof);
client.VerifySession(ephemeral.Public, proof, serverProof.Proof);
var rootKey = E2eeRecoveryProtocol.GenerateIdentity();
var keys = E2eeProtocol.GenerateKeys();
var device = E2eeRecoveryProtocol.Certify(E2eeProtocol.PublicKey(keys, user, sessionId), rootKey);
var directory = new ConversationKeys(conversation, 0, [user], [device]);
var secondKeys = E2eeProtocol.GenerateKeys();
var secondDevice = E2eeRecoveryProtocol.Certify(E2eeProtocol.PublicKey(secondKeys, Guid.NewGuid(), Guid.NewGuid()), E2eeRecoveryProtocol.GenerateIdentity());
directory = directory with { Members = [user, secondDevice.UserId], Devices = [device, secondDevice] };
var message = E2eeProtocol.Encrypt(new("Привет из .NET 🔐", []), keys, device, directory, messageId, createdAt: 1793383200000);
var code = E2eeRecoveryProtocol.GenerateCode();
var vault = E2eeRecoveryProtocol.Seal(user, 1, rootKey, code, "dotnet archive");
var credentials = new PasswordCredentials(1, salt, identity, verifier);
var envelope = PasswordProtocol.Seal(user, 1, credentials, rootKey, code, derived.ArchiveKey);
var attachment = E2eeProtocol.EncryptAttachment(Encoding.UTF8.GetBytes("attachment 🔐"));
var output = new { Warning = "PUBLIC TEST KEYS ONLY", Prime = PasswordProtocol.Parameters().Prime.ToHex(),
    Generator = PasswordProtocol.Parameters().Generator.ToHex(), Password = password, Salt = salt, Identity = identity,
    Secret = derived.Secret, ArchiveKey = derived.ArchiveKey, PrivateKey = x, Verifier = verifier,
    ClientSecret = ephemeral.Secret, ClientPublic = ephemeral.Public, ServerPublic = remote.Public,
    SessionKey = proof.Key, ClientProof = proof.Proof, ServerProof = serverProof.Proof,
    User = user, Session = sessionId, Conversation = conversation, MessageId = messageId,
    RootKey = rootKey, Keys = keys, Device = device, SecondKeys = secondKeys, SecondDevice = secondDevice, Message = message, Code = code, Vault = vault,
    Credentials = credentials, PasswordEnvelope = envelope, Attachment = Convert.ToBase64String(attachment.Data), AttachmentKey = attachment.Key };
var outputPath = args.Length == 1 ? args[0] : "test/fixtures/dotnet.json";
Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(outputPath))!);
File.WriteAllText(outputPath, JsonSerializer.Serialize(output, options));
Console.WriteLine("Wrote public .NET protocol fixtures to " + outputPath);
