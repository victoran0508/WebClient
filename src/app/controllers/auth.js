angular.module("proton.Controllers.Auth", ["proton.Auth"])

.controller("LoginController", function($rootScope, $state, $scope, authentication) {
  if ($state.is("login") && authentication.isLoggedIn()) {
    $state.go("login.unlock");
    return;
  }

  if (authentication.user) {
    $scope.user = authentication.user;
  }

  $rootScope.pageName = "Login";

  var clearErrors = function() {
    $scope.error = null;
  };

  $scope.logout = function() {
    clearErrors();
    authentication.logout();
  };

  $scope.login = function() {
    clearErrors();
    $scope.isLoading = true;

    authentication.loginWithCredentials({
      username: $("#username").val(),
      password: $("#password").val()
    }).then(
      function() {
        $state.go("login.unlock");
        $scope.user = authentication.user;
        $scope.isLoading = false;
      },
      function(err) {
        $scope.error = err;
        $scope.isLoading = false;
      }
    );
  };

  $scope.decrypt = function() {
    clearErrors();
    $scope.isLoading = true;

    authentication
      .unlockWithPassword($("#mailboxPassword").val())
      .then(
        function() {
          $state.go("secured.inbox");
          $scope.isLoading = false;
        },
        function(err) {
          $scope.error = err;
          $scope.isLoading = false;
        }
      );
  };

  $scope.keypress = function (event) {
    if (event.keyCode === 13) {
      event.preventDefault();
      if ($state.is("login.unlock")) {
        $scope.decrypt();
      } else {
        $scope.login();
      }
    }
  };
})

.controller("SecuredController", function($scope, $interval, $rootScope, $http, authentication) {
  $scope.user = authentication.user;
  $scope.logout = function() {
    authentication.logout();
  };

  var fetchUpdates = function() {
    $http.get(authentication.baseURL + "/user/updates").then(function (resp) {
      if (resp.status === 200) {
        $rootScope.unreadCount = resp.data.unread;
        $rootScope.draftsCount = resp.data.drafts;
      }
    });
  };

  var updates = $interval(fetchUpdates, 5000);
  fetchUpdates();

  $scope.$on("$destroy", function () {
    $interval.cancel(updates);
  });
})

.controller("AdminController", function($scope, authentication) {
  $scope.user = authentication.user;
  $scope.logout = function() {
    authentication.logout();
  };
});
