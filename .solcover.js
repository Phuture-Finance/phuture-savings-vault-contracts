module.exports = {
  skipFiles: ['interfaces', 'test'],
  compileCommand: 'npm run compile',
  testCommand: 'npm test',
  norpc: true,
  mocha: {
    forbidOnly: true,
    grep: '@skip-on-coverage',
    invert: true
  }
}
