pragma solidity 0.5.8;

contract roiDapp {
    struct Plant {
        uint price;
        uint payout_per_hour;
        uint energy_credits;
        uint compound_credits;
        uint tax;
    }

    struct Player {
        uint balance;
        uint credits;
        uint direct_bonus;
        uint match_bonus;
        uint totalCredits;
        uint balance_withdrawable;
        uint last_payout;
        uint last_compound;
        uint withdraw;
        uint invested;
        address upline;
        uint256 total_match_bonus;
        uint[] plants;
        uint[] plants_time;
        uint[] credits_time;
        mapping(uint8 => uint256) structure;
    }

    address payable public owner;
    uint public compoundRate;
    uint public investorCount;
    uint public totalInvested;
    uint public lastCompound;
    uint public investedNow;
    uint public direct_bonus;
    uint public match_bonus;

    uint8[] public ref_bonuses;
    Plant[] public plants;
    mapping(address => Player) public players;

    event Deposit(address indexed addr, uint value);
    event BuyPlant(address indexed addr, uint plant);
    event Withdraw(address indexed addr, uint value);
    event Compound(address indexed addr, uint value);
    event Upline(address indexed addr, address indexed upline, uint256 bonus);
    event MatchPayout(address indexed addr, address indexed from, uint256 amount);

    constructor() public {
        owner = msg.sender;
        compoundRate = 172800;
        lastCompound = now;

        plants.push(Plant({price: 99 trx, payout_per_hour: 0.165 trx, energy_credits: 2, tax: 5184000, compound_credits: 0}));
        plants.push(Plant({price: 999 trx, payout_per_hour: 2.33 trx, energy_credits: 20, tax: 129600, compound_credits: 1}));
        plants.push(Plant({price: 9999 trx, payout_per_hour: 29.16 trx, energy_credits: 200, tax: 7200, compound_credits: 3}));

        ref_bonuses.push(5);
        ref_bonuses.push(3);
    }

    function _payout(address addr) private returns(uint) {
        Player storage player = players[addr];

        uint cost = costOf(addr);
        uint payout = payoutOf(addr);

        if(payout > 0) {

            if(cost >= 1 && player.credits >= 1) {
                if(player.credits >= cost) {
                    player.credits -= cost;
                    for(uint i = 0; i < player.plants.length; i++) {
                        if((now - player.credits_time[i]) >= plants[player.plants[i]].tax) {
                            player.credits_time[i] = now - ((now - player.credits_time[i]) % plants[player.plants[i]].tax);
                        }
                    }
                } else if (player.credits < cost) {
                    player.credits = 0;
                    for(uint i = 0; i < player.plants.length; i++) {
                        if((now - player.credits_time[i]) >= plants[player.plants[i]].tax) {
                            player.credits_time[i] = now - ((now - player.credits_time[i]) % plants[player.plants[i]].tax);
                        }
                    }
                }
            }
            player.last_payout = block.timestamp;
            player.balance_withdrawable += payout;
            players[owner].balance_withdrawable += payout / 10;
            players[player.upline].match_bonus += payout / 50;
        }
        return (player.balance_withdrawable);
    }

    function _refPayout(address _addr, uint256 _amount) private {
        address up = players[_addr].upline;

        for(uint8 i = 0; i < ref_bonuses.length; i++) {
            if(up == address(0)) break;

            uint256 bonus = _amount * ref_bonuses[i] / 100;

            players[up].match_bonus += bonus;
            players[up].total_match_bonus += bonus;

            match_bonus += bonus;

            emit MatchPayout(up, _addr, bonus);

            up = players[up].upline;
        }
    }

    function _setUpline(address _addr, address _upline, uint256 _amount) private {
        if(players[_addr].upline == address(0) && _addr != owner) {
            if(players[_upline].plants.length == 0) {
                _upline = owner;
            }
            else {
                players[_addr].direct_bonus += _amount / 100;
                direct_bonus += _amount / 100;
            }

            players[_addr].upline = _upline;

            emit Upline(_addr, _upline, _amount / 100);

            for(uint8 i = 0; i < ref_bonuses.length; i++) {
                players[_upline].structure[i]++;

                _upline = players[_upline].upline;

                if(_upline == address(0)) break;
            }
        }
    }

    function _deposit(address addr, uint value) private {
        players[addr].balance += value;

        emit Deposit(addr, value);
    }

    function _buyBuild(address addr, uint plant) private {
        require(plants[plant].price > 0, "Plant not found");

        Player storage player = players[addr];

        require(player.plants.length < 50, "Max 50 plants per address");

        require(player.balance + player.balance_withdrawable >= plants[plant].price, "Insufficient funds");

        uint cost = costOf(msg.sender);
        require(cost <= player.credits, "Payout before investing more");

        if(player.balance < plants[plant].price) {
            player.balance_withdrawable -= plants[plant].price - player.balance;
            player.balance = 0;
        }
        else player.balance -= plants[plant].price;

        player.invested += plants[plant].price;
        investedNow += plants[plant].price;
        totalInvested += plants[plant].price;

        player.plants.push(plant);
        player.plants_time.push(now);
        player.credits_time.push(now);

        player.credits += plants[plant].energy_credits;
        player.totalCredits += plants[plant].energy_credits;

        emit BuyPlant(addr, plant);
    }

    function() payable external {
        revert();
    }

    function deposit(address _upline) payable external {
        require(msg.value >= 10 trx, "Insufficient amount");
        _deposit(msg.sender, msg.value);

        if(players[msg.sender].last_payout == 0) {
            players[msg.sender].last_payout = now;
            players[msg.sender].last_compound = now;
            investorCount++;
        }

        _setUpline(msg.sender, _upline, msg.value);
        _refPayout(msg.sender, msg.value);

        //dev fee

        players[owner].balance_withdrawable += msg.value / 10;
    }

    function buyBuild(uint build) external {
        _buyBuild(msg.sender, build);
    }

    function buyBuilds(uint[] calldata _builds) external {
        require(_builds.length > 0, "Empty plants");
        require(_builds.length <= 10, "Less than/or 10 plants");

        for(uint i = 0; i < _builds.length; i++) {
            _buyBuild(msg.sender, _builds[i]);
        }
    }

    function withdraw() external {
        Player storage player = players[msg.sender];

        uint total = _payout(msg.sender) + player.match_bonus + player.direct_bonus;

        require(total > 0 || player.direct_bonus > 0 || player.match_bonus > 0, "Small value");
        compoundUpdate();

        player.balance_withdrawable = 0;
        player.match_bonus = 0;
        player.direct_bonus = 0;
        player.withdraw += total;

        if(total > address(this).balance) {
            total = (total * address(this).balance) / total;
        }
        (bool success, ) = msg.sender.call.value(total)("");
        require(success, "Transfer failed.");
        emit Withdraw(msg.sender, total);
    }

    function payoutOf(address addr) view public returns(uint value) {
        Player storage player = players[addr];

        uint credits = player.credits;
        uint cost = costOf(addr);

        for(uint i = 0; i < player.plants.length; i++) {
            uint from = player.last_payout > player.plants_time[i] ? player.last_payout : player.plants_time[i];
            if(from < now && credits >= 1) {
              if(cost <= credits) {
                  value += ((now - from) / 3600) * plants[player.plants[i]].payout_per_hour;
                  credits -= (now - player.credits_time[i]) / plants[players[addr].plants[i]].tax;
              } else if (cost > credits && player.credits_time[i] > 0) {
                  value += ((plants[player.plants[i]].tax * credits) / 3600) * plants[player.plants[i]].payout_per_hour;
                  credits = 0;
              }
            }
        }
        if(credits < player.totalCredits / 2) {
            value = value / 2;
        }
        else if(credits < ((player.totalCredits * 100) / 125)) {
            value = (value * 100) / 125;
        }
        return value;
    }

    function costOf(address addr) view public returns(uint cost) {

        for(uint i = 0; i < players[addr].plants.length; i++) {
            if(now - players[addr].credits_time[i] > plants[players[addr].plants[i]].tax) {
                cost += (now - players[addr].credits_time[i]) / plants[players[addr].plants[i]].tax;
            }
        }
        return cost;
    }

    function compound() external {
        Player storage player = players[msg.sender];

        require(now - player.last_compound > compoundRate, "Insufficient time");
        require(player.credits >= 1, "Insufficient credits");
        compoundUpdate();

        uint total = payoutOf(msg.sender);

        require(total > 0, "Insufficient value");

        if(total > 0) {
            player.last_compound = now;
            player.last_payout = now;
            player.balance += total;
            for(uint i = 0; i < player.plants.length; i++) {
                if(now - player.credits_time[i] >= compoundRate && player.credits_time[i] > 0) {
                    player.credits += ((now - player.credits_time[i]) / compoundRate) * plants[player.plants[i]].compound_credits;
                    player.credits_time[i] = now - ((now - player.credits_time[i]) % compoundRate);
                }
            }
            if (player.credits > player.totalCredits) {
                player.credits = player.totalCredits;
            }
        }
        emit Compound(msg.sender, total);
    }

    function compoundOf() view external returns(uint value){
        Player storage player = players[msg.sender];

        if((now - player.last_compound) >= compoundRate) {
            for(uint i = 0; i < player.plants.length; i++) {
                if(now - player.credits_time[i] >= compoundRate) {
                    value += ((now - player.credits_time[i]) / compoundRate) * plants[player.plants[i]].compound_credits;
                }
            }
            if (value + player.credits > player.totalCredits) {
                value = player.totalCredits - player.credits;
            }
        }
        return value;
    }

    function compoundUpdate() private {
        if((now - lastCompound) / compoundRate >= 1) {
            if(investedNow >= 99 trx) {
                lastCompound = now;
                compoundRate += (1 * (investedNow / 99 trx));
                investedNow = investedNow % 99 trx;
            }
        }
    }

    function donate(address addr) payable public {
        players[addr].balance += msg.value;
    }
}
