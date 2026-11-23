// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Minimal interfaces for Lane 4 fork tests, hand-written from the
// Sourcify-verified deployed source (== branch feature/v4-builders tip a4a8083).

struct Subnet {
    string name;
    address admin;
    uint128 unusedStorage1_V4Update;
    uint128 withdrawLockPeriodAfterDeposit;
    uint128 unusedStorage2_V4Update;
    uint256 minimalDeposit;
    address claimAdmin;
}

struct SubnetMetadata {
    string slug;
    string description;
    string website;
    string image;
}

interface IBuildersV4Min {
    function feeConfig() external view returns (address);
    function buildersTreasury() external view returns (address);
    function rewardPool() external view returns (address);
    function depositToken() external view returns (address);
    function minimalWithdrawLockPeriod() external view returns (uint256);
    function subnetCreationFeeAmount() external view returns (uint256);
    function networkShare() external view returns (uint256);
    function networkShareOwner() external view returns (address);
    function owner() external view returns (address);
    function allSubnetsData() external view returns (uint256, uint256, uint256, uint256);
    function allSubnetsDataV4() external view returns (uint256, uint256, uint256, uint128);
    function subnets(bytes32)
        external
        view
        returns (string memory, address, uint128, uint128, uint128, uint256, address);
    function subnetsData(bytes32) external view returns (uint128, uint256, uint256, uint256, uint256);
    function usersData(address, bytes32) external view returns (uint128, uint128, uint256, uint256);
    function getSubnetId(string memory) external view returns (bytes32);
    function getSubnetIdOld(string memory) external pure returns (bytes32);
    function createSubnet(Subnet calldata subnet_, SubnetMetadata calldata metadata_) external;
    function editSubnet(bytes32 subnetId_, Subnet calldata newSubnet_) external;
    function deposit(bytes32 subnetId_, uint256 amount_) external;
    function withdraw(bytes32 subnetId_, uint256 amount_) external;
    function claim(bytes32 subnetId_, address receiver_) external;
    function getCurrentSubnetsRewards() external view returns (uint256);
    function getCurrentSubnetRewards(bytes32 subnetId_) external view returns (uint256);
    function FEE_CLAIM_OPERATION() external view returns (bytes32);
}

interface ITreasuryMin {
    function builders() external view returns (address);
    function rewardToken() external view returns (address);
    function distributedRewards() external view returns (uint256);
    function sendRewards(address receiver_, uint256 amount_) external;
    function withdraw(address receiver_, uint256 amount_) external;
}

interface IFeeConfigMin {
    function getFeeAndTreasuryForOperation(address sender_, bytes32 operation_)
        external
        view
        returns (uint256, address);
    function getFeeAndTreasury(address sender_) external view returns (uint256, address);
}

interface IRewardPoolMin {
    function getPeriodRewards(uint256 index_, uint128 startTime_, uint128 endTime_)
        external
        view
        returns (uint256);
    function isRewardPoolExist(uint256 index_) external view returns (bool);
    function rewardPools(uint256)
        external
        view
        returns (uint128, uint128, uint256, uint256, bool);
}

interface IMOR {
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
}
