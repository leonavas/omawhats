.pragma library
.import "Util.js" as U

// What each kind of message is called where only a word fits (the chat
// list, quotes, notifications), with the icon WhatsApp puts before it,
// and what the notices in a chat say. In Portuguese or English.

function tr(lang, en, pt) { return String(lang).indexOf("pt") === 0 ? pt : en }

function parseX(x) {
  if (!x) return {}
  if (typeof x === "object") return x
  try { return JSON.parse(x) || {} } catch (e) { return {} }
}

// {icon, text, italic} for a message (or a chat row's last message):
// m has kind, text and, for some kinds, x, secs and file.
function short(m, lang) {
  var k = m.kind || "text"
  var x = parseX(m.x)
  var t = m.text || ""
  switch (k) {
  case "text": case "card": return { icon: "", text: t }
  case "image": return { icon: "camera", text: t || tr(lang, "Photo", "Foto") }
  case "video": return { icon: "video", text: t || tr(lang, "Video", "Vídeo") }
  case "ptv": return { icon: "ptv", text: tr(lang, "Video message", "Mensagem de vídeo") }
  case "gif": return { icon: "gif", text: t || "GIF" }
  case "ptt": return { icon: "mic", text: (m.secs || (m.media && m.media.secs)) ? U.duration(m.secs || m.media.secs) : tr(lang, "Voice message", "Mensagem de voz") }
  case "audio": return { icon: "headphones", text: tr(lang, "Audio", "Áudio") }
  case "document": return { icon: "document", text: t || m.file || (m.media && m.media.name) || tr(lang, "Document", "Documento") }
  case "sticker": return { icon: "sticker", text: tr(lang, "Sticker", "Figurinha") }
  case "location": return { icon: "location", text: (x.loc && x.loc.name) || tr(lang, "Location", "Localização") }
  case "live_location": return { icon: "liveLocation", text: tr(lang, "Live location", "Localização em tempo real") }
  case "contact": {
    var cs = x.contacts || []
    var name = cs.length > 1 ? tr(lang, cs.length + " contacts", cs.length + " contatos") : (cs.length ? cs[0].name : (t || tr(lang, "Contact", "Contato")))
    return { icon: "person", text: name }
  }
  case "poll": return { icon: "poll", text: t }
  case "event": return { icon: "event", text: t }
  case "invite": return { icon: "link", text: tr(lang, "Group invite", "Convite para grupo") + ((x.invite && x.invite.group) ? ": " + x.invite.group : "") }
  case "call": {
    var c = x.call || {}
    var missed = c.outcome === "missed"
    return { icon: missed ? "callMissed" : (c.video ? "video" : "call"),
             text: c.video ? (missed ? tr(lang, "Missed video call", "Chamada de vídeo perdida") : tr(lang, "Video call", "Chamada de vídeo"))
                           : (missed ? tr(lang, "Missed voice call", "Chamada de voz perdida") : tr(lang, "Voice call", "Chamada de voz")),
             danger: missed }
  }
  case "revoked": return { icon: "nosign", text: m.from_me ? tr(lang, "You deleted this message", "Você apagou esta mensagem") : tr(lang, "This message was deleted", "Esta mensagem foi apagada"), italic: true }
  case "view_once": {
    var of = x.of || "image"
    return { icon: "camera", text: of === "video" ? tr(lang, "View once video", "Vídeo de visualização única") : of === "ptt" ? tr(lang, "View once voice message", "Mensagem de voz de visualização única") : tr(lang, "View once photo", "Foto de visualização única") }
  }
  case "placeholder": return { icon: "clock", text: tr(lang, "Waiting for this message", "Aguardando esta mensagem"), italic: true }
  case "system": return { icon: "", text: systemText(x.sys || {}, m.name, m.from_me, lang) }
  case "unsupported": return { icon: "", text: tr(lang, "This message can't be shown here", "Não é possível exibir esta mensagem aqui"), italic: true }
  }
  return { icon: "", text: t }
}

function names(list, lang) {
  var ns = (list || []).map(function(p) { return p.name || U.phone(String(p.jid || "").split("@")[0]) })
  if (ns.length <= 1) return ns.join("")
  return ns.slice(0, -1).join(", ") + tr(lang, " and ", " e ") + ns[ns.length - 1]
}

// What a notice says: who did what. actor is the sender's name ("" for you).
function systemText(sys, actor, fromMe, lang) {
  var who = fromMe || !actor ? tr(lang, "You", "Você") : actor
  var people = names(sys.people, lang)
  var v = sys.value
  switch (sys.type) {
  case "group_create": return tr(lang, who + " created group \"" + (v || "") + "\"", who + " criou o grupo \"" + (v || "") + "\"")
  case "group_subject": return tr(lang, who + " changed the group name to \"" + v + "\"", who + " mudou o nome do grupo para \"" + v + "\"")
  case "group_icon": return tr(lang, who + " changed this group's icon", who + " mudou a imagem deste grupo")
  case "group_description": return tr(lang, who + " changed the group description", who + " mudou a descrição do grupo")
  case "group_restrict": return v ? tr(lang, who + " changed this group's settings to allow only admins to edit this group's info", who + " mudou as configurações do grupo para permitir que somente admins editem os dados do grupo")
                                  : tr(lang, who + " changed this group's settings to allow all members to edit this group's info", who + " mudou as configurações do grupo para permitir que todos os membros editem os dados do grupo")
  case "group_announce": return v ? tr(lang, who + " changed this group's settings to allow only admins to send messages to this group", who + " mudou as configurações do grupo para permitir que somente admins enviem mensagens")
                                   : tr(lang, who + " changed this group's settings to allow all members to send messages to this group", who + " mudou as configurações do grupo para permitir que todos os membros enviem mensagens")
  case "group_add": return tr(lang, who + " added " + people, who + " adicionou " + people)
  case "group_remove": return tr(lang, who + " removed " + people, who + " removeu " + people)
  case "group_leave": return tr(lang, (people || who) + " left", (people || who) + " saiu")
  case "group_join": return tr(lang, (people || who) + " joined using an invite link", (people || who) + " entrou usando o link de convite deste grupo")
  case "group_promote": return tr(lang, people + " is now an admin", people + " agora é admin")
  case "group_demote": return tr(lang, people + " is no longer an admin", people + " não é mais admin")
  case "change_number": return tr(lang, (people || who) + " changed their phone number", (people || who) + " mudou de número de telefone")
  case "ephemeral": {
    var secs = Number(v || 0)
    if (!secs) return tr(lang, who + " turned off disappearing messages", who + " desativou as mensagens temporárias")
    var d = secs >= 86400 ? Math.round(secs / 86400) : 0
    var span = d >= 90 ? tr(lang, "90 days", "90 dias") : d >= 7 ? tr(lang, "7 days", "7 dias") : tr(lang, "24 hours", "24 horas")
    return tr(lang, who + " turned on disappearing messages. New messages will disappear from this chat " + span + " after they're sent.",
                    who + " ativou as mensagens temporárias. As novas mensagens vão desaparecer desta conversa " + span + " após o envio.")
  }
  case "security_code": return tr(lang, "Your security code with " + (people || actor) + " changed.", "Seu código de segurança com " + (people || actor) + " mudou.")
  case "pin": return tr(lang, who + " pinned a message", who + " fixou uma mensagem")
  case "unpin": return tr(lang, who + " unpinned a message", who + " desafixou uma mensagem")
  }
  return ""
}

// Errors the bridge reports by code, as the app says them.
function error(code, lang) {
  var m = {
    send: ["Couldn't send the message", "Não foi possível enviar a mensagem"],
    send_file: ["Couldn't send the file", "Não foi possível enviar o arquivo"],
    read_only_official: ["Only WhatsApp can send messages here", "Somente o WhatsApp pode enviar mensagens"],
    read_only_admins: ["Only admins can send messages", "Somente admins podem enviar mensagens"],
    read_only_left: ["You can't send messages to this group because you're no longer a member", "Você não pode enviar mensagens para este grupo porque não é mais participante"],
    read_only_cant: ["You can't send messages to this chat", "Não é possível enviar mensagens para esta conversa"],
    pin_limit: ["You can only pin up to 3 chats", "Você só pode fixar até 3 conversas"],
    archive: ["Couldn't archive the chat", "Não foi possível arquivar a conversa"],
    pin: ["Couldn't pin the chat", "Não foi possível fixar a conversa"],
    unread: ["Couldn't mark the chat as unread", "Não foi possível marcar como não lida"],
    mute: ["Couldn't mute the chat", "Não foi possível silenciar a conversa"],
    favorite: ["Couldn't change your favorites", "Não foi possível alterar as favoritas"],
    clear: ["Couldn't clear the chat", "Não foi possível limpar a conversa"],
    delete_chat: ["Couldn't delete the chat", "Não foi possível apagar a conversa"],
    delete_for_me: ["Couldn't delete on your other devices", "Não foi possível apagar nos outros aparelhos"],
    revoke: ["Couldn't delete for everyone", "Não foi possível apagar para todos"],
    edit: ["Couldn't edit the message", "Não foi possível editar a mensagem"],
    react: ["Couldn't react", "Não foi possível reagir"],
    star: ["Couldn't star the message", "Não foi possível favoritar a mensagem"],
    forward: ["Couldn't forward the message", "Não foi possível encaminhar a mensagem"],
    forward_some: ["Some messages can't be forwarded", "Algumas mensagens não podem ser encaminhadas"],
    sticker_fav: ["Couldn't change your favorite stickers", "Não foi possível alterar as figurinhas favoritas"],
    sticker: ["Couldn't send the sticker", "Não foi possível enviar a figurinha"],
    logout: ["Couldn't disconnect", "Não foi possível desconectar"],
    connect: ["Couldn't connect to WhatsApp", "Não foi possível conectar ao WhatsApp"],
    pair: ["Couldn't link the device", "Não foi possível conectar o aparelho"],
    pair_phone: ["Couldn't get a code for this number", "Não foi possível gerar um código para este número"],
    pair_phone_number: ["Enter the full phone number, with the country code", "Digite o número completo, com o código do país"],
    photo: ["Couldn't load the photo", "Não foi possível carregar a foto"],
    fatal: ["WhatsApp stopped", "O WhatsApp parou"]
  }
  var e = m[code]
  return e ? tr(lang, e[0], e[1]) : tr(lang, "Something went wrong", "Algo deu errado")
}
