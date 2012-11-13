sinon = require 'sinon'
chai = require 'chai'

expect = chai.expect

Missilelauncher = require '../lib/missilelauncher'

describe 'Missilelauncher', ->
  
  beforeEach ->
    @spy = sinon.spy()
    @clock = sinon.useFakeTimers()
    @device = write: @spy
    @missilelauncher = new Missilelauncher device: @device, config: {log: false, FIRING_TIME: 100}
    
  afterEach ->
    @clock.restore()
    
  it 'should populate config', ->
    for property in ['FULL_VERTICAL_ANGLE', 'FULL_HORIZONTAL_ANGLE', 'HORIZONTAL_TURN_RATE', 'VERTICAL_TURN_RATE']
      expect(@missilelauncher.config[property]).to.be.a 'number'
    
  describe '#sendCommand', ->
    
    it 'should parse string commands', ->
      @missilelauncher.sendCommand 'UP'
      expect(@spy.called).to.equal true
    
    it 'should fail on everything else except string', ->
      expect(@missilelauncher.sendCommand {}).to.equal false
      expect(@spy.called).to.equal false
    
    it 'should send correct command', ->
      @missilelauncher.sendCommand 'STOP'
      expect(@spy.called).to.equal true
      expect(@spy.getCall(0).args[0][1]).to.equal 0x20
      
    it 'should work with lowercase command', ->
      @missilelauncher.sendCommand 'stop'
      expect(@spy.called).to.equal true
      expect(@spy.getCall(0).args[0][1]).to.equal 0x20
      
  describe 'commands', ->

    beforeEach ->
      sinon.spy @missilelauncher, 'sendCommand'
      
    afterEach ->
      @missilelauncher.sendCommand.restore()

    describe '#move', ->
      
      it 'should not move if already moving', ->
        @missilelauncher.moving = true
        expect(@missilelauncher.move 'UP', 100).to.be.undefined
        expect(@missilelauncher.sendCommand.called).to.equal false
        
      it 'should send command and stop after time', (done) ->
        ready = @missilelauncher.move 'UP', 100
        expect(@missilelauncher.moving).to.equal true
        ready.then done
        expect(@missilelauncher.sendCommand.callCount).to.equal 1
        expect(@missilelauncher.sendCommand.getCall(0).args[0]).to.equal 'UP'
        @clock.tick(99)
        expect(@missilelauncher.sendCommand.callCount).to.equal 1
        @clock.tick(1)
        expect(@missilelauncher.moving).to.equal false
        expect(@missilelauncher.sendCommand.callCount).to.equal 2
        expect(@missilelauncher.sendCommand.getCall(1).args[0]).to.equal 'STOP'

    describe '#fire', ->
      
      it 'should fire and resolve after firing timer has elapsed', (done) ->
        ready = @missilelauncher.fire()
        ready.then done
        expect(@missilelauncher.moving).to.equal true
        expect(@missilelauncher.sendCommand.called).to.equal true
        expect(@missilelauncher.sendCommand.getCall(0).args[0]).to.equal 'FIRE'
        @clock.tick(99)
        expect(@missilelauncher.moving).to.equal true
        @clock.tick(1)
        expect(@missilelauncher.moving).to.equal false
        