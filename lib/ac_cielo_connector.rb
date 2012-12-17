# encoding: UTF-8

require 'net/https'
require 'uri'
require 'builder'
require 'rexml/document'


PAIS = '097'
REAL = '986'

class FormaPagamentoCielo
  CREDITO_VISTA = 1
  PARCELADO_LOJA = 2
  PARCELADO_ADMINISTRADORA = 3
  DEBITO = 'A'
end

class IndicadorAutorizacao
  NAO_AUTORIZAR = 0
  AUTORIZAR_SE_AUTENTICADA = 1
  AUTORIZAR_SEMPRE = 2
end

class StatusTransacao
  CRIADA = 0
  ANDAMENTO = 1
  AUTENTICADA = 2
  NAO_AUTENTICADA = 3
  AUTORIZADA = 4
  NAO_AUTORIZADA = 5
  CAPTURADA = 6
  NAO_CAPTURADA = 8
  CANCELADA = 9
end

class RequisicaoCielo
  @@NUMERO_CIELO = '1028669612'
  @@CHAVE_CIELO = '0047f91507bc5737acd2781b5b56548321604ff28d3208756ca08e3334fbb9a9'
  @@NOME_LOJA = 'Mestre SMS'

  def self.NUMERO_CIELO=(value)
    @@NUMERO_CIELO = value
  end

  def self.CHAVE_CIELO=(value)
    @@CHAVE_CIELO = value
  end

  def self.NOME_LOJA=(value)
    @@NOME_LOJA = value
  end
  
  SERVIDOR_TESTE = 'qasecommerce.cielo.com.br' 
  SERVIDOR_PRODUCAO = 'ecommerce.cbmp.com.br'
  
  SERVICO_ECOMMERCE = '/servicos/ecommwsec.do'
  
  AMBIENTE_TESTE = 1
  AMBIENTE_PRODUCAO = 2
  
  def initialize(ambiente = AMBIENTE_PRODUCAO)
    @ambiente = ambiente
  end
  
  def processa_requisicao(mensagem)
    if @ambiente == AMBIENTE_PRODUCAO
      srv = SERVIDOR_PRODUCAO
    else
      srv = SERVIDOR_TESTE
    end
      
    http = Net::HTTP::new(srv, 443)
    http.use_ssl = true

    req = Net::HTTP::Post.new(SERVICO_ECOMMERCE)        
    
    req.set_form_data(:mensagem => mensagem)

    res = http.start { |x| x.request(req) }
    res.error! unless Net::HTTPSuccess === res

    res.body
  end
  
  def gera_dados_ec(no_raiz, opcoes = {})
    opcoes = {:incluir_dados_loja => true}.merge(opcoes)
    no_raiz.tag!("dados-ec") do |dec|
      dec.numero(@@NUMERO_CIELO)
      dec.chave(@@CHAVE_CIELO)
      if opcoes[:incluir_dados_loja]
        dec.nome(@@NOME_LOJA)
        dec.tag!("codigo-pais", PAIS)
      end
    end
  end
end

class RequisicaoAutenticacao < RequisicaoCielo
  
  def processa(propriedades_pedido)
    p = propriedades_pedido.symbolize_keys
    #validar dados
    
    dados = ''
    x = Builder::XmlMarkup.new(:target => dados, :indent => 0)

    x.instruct!
    x.tag!("requisicao-autenticacao",{"id" => 1, "versao" => "1.0.0", "xmlns" => "http://ecommerce.cbmp.com.br"}) do |ra|
      gera_dados_ec(ra)
      ra.tag!("dados-pedido") do |dp|
        dp.numero(p[:numero])
        dp.valor((p[:valor] * 100).to_i)
        dp.moeda(REAL)
        dp.tag!("data-hora", p[:data_hora].strftime("%Y-%m-%dT%H:%M:%S"))
        dp.descricao(p[:descricao])
      end
      ra.tag!("forma-pagamento") do |fp|
        fp.produto(p[:forma_pagamento].to_s)
        fp.parcelas(p[:parcelas].try(:to_s) || '1')
      end
      ra.tag!("url-retorno", p[:url_retorno].to_s)
      ra.autorizar(p[:indicador_autorizacao].to_s)
      ra.capturar(p[:captura_automatica].to_s)
    end
    res = processa_requisicao(dados)
    RetornoRequisicao.new(res)
  end
end

class RequisicaoAutorizacao
  
end

class RequisicaoCaptura
  
end

class RequisicaoCancelamento < RequisicaoCielo
  def processa(tid)
    dados = ''
    x = Builder::XmlMarkup.new(:target => dados, :indent => 0)

    x.instruct!
    x.tag!("requisicao-cancelamento",{"id" => 4, "versao" => "1.0.0", "xmlns" => "http://ecommerce.cbmp.com.br"}) do |ra|
      x.tid tid
      gera_dados_ec(ra, :incluir_dados_loja => false)
    end
    res = processa_requisicao(dados)
    RetornoRequisicao.new(res)
  end
end

class RequisicaoConsulta < RequisicaoCielo
  def processa(tid)
    dados = ''
    x = Builder::XmlMarkup.new(:target => dados, :indent => 0)

    x.instruct!
    x.tag!("requisicao-consulta",{"id" => 5, "versao" => "1.0.0", "xmlns" => "http://ecommerce.cbmp.com.br"}) do |ra|
      x.tid tid
      gera_dados_ec(ra, :incluir_dados_loja => false)
    end
    res = processa_requisicao(dados)
    RetornoRequisicao.new(res)
  end
end

class RetornoRequisicao
  attr_reader :tid, :erro, :mensagem_erro, :status, :url_autenticacao
  
  def initialize(dados)
    doc = REXML::Document.new(dados)
    @erro = false
    if doc.elements['transacao']
      @tid = doc.elements['transacao'].elements['tid'].text
      @status = doc.elements['transacao'].elements['status'].text.to_i
      @url_autenticacao = doc.elements['transacao'].elements['url-autenticacao'].try(:text)
    else 
      @erro = true
      if doc.elements['erro']
        @mensagem_erro = doc.elements['erro'].elements['mensagem'].text
      else
        @mensagem_erro = 'Documento inválido'
      end
    end
  end
end
